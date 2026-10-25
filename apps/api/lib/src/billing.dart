import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import 'auth.dart';
import 'config.dart';
import 'database.dart';
import 'finance.dart';
part 'accounting_connector.dart';

class BillingService {
  BillingService(
    this.database,
    this.finance,
    this.config, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    database.db.execute(
      '''CREATE TABLE IF NOT EXISTS billing_profiles(scope TEXT PRIMARY KEY,payload TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1);
      CREATE TABLE IF NOT EXISTS billing_sequences(scope TEXT NOT NULL,year INTEGER NOT NULL,next INTEGER NOT NULL,PRIMARY KEY(scope,year));
      CREATE TABLE IF NOT EXISTS billing_documents(id TEXT PRIMARY KEY,scope TEXT NOT NULL,org_id TEXT,store_id TEXT,order_id TEXT NOT NULL REFERENCES orders(id),
        source TEXT NOT NULL,kind TEXT NOT NULL,number TEXT NOT NULL,payload TEXT NOT NULL,hash TEXT NOT NULL,created_at TEXT NOT NULL,retention_until TEXT NOT NULL,pdf BLOB,pdf_hash TEXT,
        UNIQUE(scope,source),UNIQUE(scope,number));
      CREATE TABLE IF NOT EXISTS billing_pending(order_id TEXT PRIMARY KEY REFERENCES orders(id),reason TEXT NOT NULL,created_at TEXT NOT NULL);''',
    );
    initializeAccounting();
    if (config.billingSellerModel.isNotEmpty) {
      if (model != null && model != config.billingSellerModel) {
        throw StateError(
          'BILLING_SELLER_MODEL conflicts with the existing billing model. '
          'Resolve the configuration before starting; the stored model was not changed.',
        );
      }
      if (model == null) setModel(config.billingSellerModel);
    }
  }
  final MarketplaceDatabase database;
  final FinanceService finance;
  final ServerConfig config;
  final DateTime Function() clock;
  String get now => clock().toUtc().toIso8601String();
  String get date => tz.TZDateTime.from(
    clock(),
    tz.getLocation('Europe/Bratislava'),
  ).toIso8601String().substring(0, 10);
  String? get model =>
      database.db
              .select(
                "SELECT payload FROM platform_settings WHERE name='billingModel'",
              )
              .firstOrNull?['payload']
          as String?;
  Map<String, dynamic> profile(String scope) {
    final row = database.db.select(
      'SELECT * FROM billing_profiles WHERE scope=?',
      [scope],
    ).firstOrNull;
    return row == null
        ? {'configured': false, 'version': 0}
        : {
            ...database.decode(row['payload'] as String),
            'configured': true,
            'version': row['version'],
          };
  }

  void setModel(String value) {
    if (!{'merchantSeller', 'platformSeller'}.contains(value)) {
      throw const ApiFailure(400, 'Urči zmluvného predávajúceho.');
    }
    if (config.billingSellerModel.isNotEmpty &&
        value != config.billingSellerModel) {
      throw const ApiFailure(
        409,
        'Predávajúci je určený konfiguráciou servera. Zmena vyžaduje schválenú migráciu.',
      );
    }
    database.db.execute(
      "INSERT INTO platform_settings(name,payload) VALUES('billingModel',?) ON CONFLICT(name) DO UPDATE SET payload=excluded.payload,version=version+1",
      [value],
    );
  }

  Map<String, dynamic> saveProfile(
    String scope,
    Map<String, dynamic> body,
  ) => database.transaction(() {
    final before = profile(scope);
    if (body['version'] != before['version']) {
      throw const ApiFailure(409, 'Fakturačný profil sa zmenil. Obnov ho.');
    }
    final output = <String, dynamic>{};
    for (final key in [
      'name',
      'address',
      'companyId',
      'country',
      'contactEmail',
      'prefix',
    ]) {
      final value = stringField(body, key, max: 500);
      if (value.isEmpty) throw ApiFailure(400, 'Vyplň fakturačné pole $key.');
      output[key] = value;
    }
    if (!RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(output['prefix'] as String) ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(output['country'] as String)) {
      throw const ApiFailure(
        400,
        'Predpona má 2 až 12 veľkých písmen/číslic; krajina je dvojmiestny kód.',
      );
    }
    if (!RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    ).hasMatch(output['contactEmail'] as String)) {
      throw const ApiFailure(400, 'Doplň platný fakturačný e-mail.');
    }
    final taxMode = stringField(body, 'taxMode');
    if (!{'vat', 'notVat'}.contains(taxMode)) {
      throw const ApiFailure(400, 'Vyber daňový režim.');
    }
    output['taxMode'] = taxMode;
    output['vatId'] = stringField(body, 'vatId', max: 50);
    output['taxId'] = stringField(body, 'taxId', max: 50);
    if (taxMode == 'vat' && (output['vatId'] as String).isEmpty) {
      throw const ApiFailure(400, 'Platiteľ DPH musí uviesť IČ DPH.');
    }
    final days = body['retentionDays'];
    if (days is! int || days < 1 || days > 36500) {
      throw const ApiFailure(400, 'Zadaj schválenú retenčnú dobu v dňoch.');
    }
    output['retentionDays'] = days;
    final rates = Map<String, dynamic>.from(body['rates'] as Map? ?? {});
    if (rates.keys.any(
          (k) =>
              !{...FoodCategory.values.map((c) => c.name), 'fee'}.contains(k),
        ) ||
        rates.values.any((v) => v is! int || v < 0 || v > 10000)) {
      throw const ApiFailure(
        400,
        'Sadzby zadaj v bázických bodoch 0 až 10000.',
      );
    }
    output['rates'] = rates;
    output['demo'] = config.demoShowcase;
    database.db.execute(
      'INSERT INTO billing_profiles(scope,payload,version) VALUES(?,?,1) ON CONFLICT(scope) DO UPDATE SET payload=excluded.payload,version=version+1',
      [scope, jsonEncode(output)],
    );
    return profile(scope);
  });
  void prepareDemo() {
    if (!config.demoShowcase) return;
    if (model == null) setModel('merchantSeller');
    final scopes = [
      'platform',
      ...database.db
          .select('SELECT id FROM merchant_organizations')
          .map((r) => r['id'] as String),
    ];
    for (final scope in scopes) {
      if (profile(scope)['configured'] == true) continue;
      final name = scope == 'platform'
          ? 'DEMO · Save Food'
          : database.db.select(
                  'SELECT name FROM merchant_organizations WHERE id=?',
                  [scope],
                ).first['name']
                as String;
      saveProfile(scope, {
        'version': 0,
        'name': name,
        'address': 'DEMO · Ilustračná adresa, Bratislava',
        'companyId': '00000000',
        'country': 'SK',
        'contactEmail': 'billing@demo.nevyhadzuj.test',
        'prefix': scope == 'platform' ? 'DEMOP' : 'DEMOS',
        'taxMode': 'notVat',
        'vatId': '',
        'taxId': '',
        'retentionDays': 3650,
        'rates': {},
      });
    }
  }

  Map<String, dynamic> _issuer(String scope) {
    final p = profile(scope);
    if (p['configured'] != true) {
      throw const ApiFailure(409, 'Chýba fakturačný profil dodávateľa.');
    }
    return p;
  }

  Map<String, dynamic> _write(
    String scope,
    String source,
    String kind,
    String order,
    String? org,
    String? store,
    Map<String, dynamic> issuer,
    Map<String, dynamic> buyer,
    List<Map<String, dynamic>> units,
    String title, {
    String? original,
    String? originalNumber,
    String? supplied,
    String? reason,
    int? unitPrice,
  }) => database.transaction(() {
    final old = database.db.select(
      'SELECT id,payload FROM billing_documents WHERE scope=? AND source=?',
      [scope, source],
    );
    if (old.isNotEmpty) return read(old.first['id'] as String);
    final year = int.parse(date.substring(0, 4));
    database.db.execute(
      'INSERT OR IGNORE INTO billing_sequences VALUES(?,?,1)',
      [scope, year],
    );
    final sequence =
        database.db.select(
              'SELECT next FROM billing_sequences WHERE scope=? AND year=?',
              [scope, year],
            ).first['next']
            as int;
    database.db.execute(
      'UPDATE billing_sequences SET next=next+1 WHERE scope=? AND year=?',
      [scope, year],
    );
    final id = const Uuid().v4(),
        number =
            '${issuer['prefix']}-$year-${sequence.toString().padLeft(6, '0')}';
    final factor = kind == 'creditNote' ? -1 : 1;
    int sum(String key) =>
        units.fold<int>(0, (n, u) => n + (u[key] as int)) * factor;
    final payload = {
      'id': id,
      'number': number,
      'kind': kind,
      'source': source,
      'orderId': order,
      'orgId': org,
      'storeId': store,
      'issuedAt': date,
      'supplyDate': supplied ?? date,
      'currency': 'EUR',
      'issuer': issuer,
      'buyer': buyer,
      'originalDocumentId': original,
      'originalNumber': originalNumber,
      'reason': reason,
      'title': title,
      'units': units,
      'quantity': units.length,
      'unitPrice': unitPrice,
      'net': sum('net'),
      'vat': sum('vat'),
      'gross': sum('gross'),
      'demo': config.demoShowcase,
    };
    final encoded = jsonEncode(payload),
        hash = sha256.convert(utf8.encode(encoded)).toString();
    database.db.execute(
      'INSERT INTO billing_documents(id,scope,org_id,store_id,order_id,source,kind,number,payload,hash,created_at,retention_until) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        scope,
        org,
        store,
        order,
        source,
        kind,
        number,
        encoded,
        hash,
        now,
        clock()
            .toUtc()
            .add(Duration(days: issuer['retentionDays'] as int))
            .toIso8601String(),
      ],
    );
    return {...payload, 'hash': hash};
  });
  Map<String, dynamic> read(String id) {
    final row = database.db.select(
      'SELECT payload,hash FROM billing_documents WHERE id=?',
      [id],
    ).firstOrNull;
    if (row == null) throw const ApiFailure(404, 'Doklad neexistuje.');
    if (sha256.convert(utf8.encode(row['payload'] as String)).toString() !=
        row['hash']) {
      throw const ApiFailure(503, 'Integrita dokladu sa musí preveriť.');
    }
    return {...database.decode(row['payload'] as String), 'hash': row['hash']};
  }

  List<Map<String, dynamic>> forOrder(String id) => database.db
      .select(
        'SELECT id FROM billing_documents WHERE order_id=? ORDER BY rowid',
        [id],
      )
      .map((r) => read(r['id'] as String))
      .toList();
  Map<String, dynamic> page(String? scope, Map<String, String> query) {
    final before = int.tryParse(query['before'] ?? '');
    if (query.containsKey('before') && before == null) {
      throw const ApiFailure(400, 'Neplatná stránka dokladov.');
    }
    final from = DateTime.tryParse(query['from'] ?? ''),
        to = DateTime.tryParse(query['to'] ?? '');
    if ((query.containsKey('from') && from == null) ||
        (query.containsKey('to') && to == null) ||
        from != null && to != null && !from.isBefore(to)) {
      throw const ApiFailure(400, 'Neplatné obdobie dokladov.');
    }
    final rows = database.db.select(
      'SELECT rowid cursor,id FROM billing_documents WHERE (? IS NULL OR scope=?) AND (? IS NULL OR rowid<?) AND (? IS NULL OR created_at>=?) AND (? IS NULL OR created_at<?) ORDER BY rowid DESC LIMIT 51',
      [
        scope,
        scope,
        before,
        before,
        from?.toIso8601String(),
        from?.toIso8601String(),
        to?.toIso8601String(),
        to?.toIso8601String(),
      ],
    );
    return {
      'rows': rows
          .take(50)
          .map((r) => {...read(r['id'] as String), 'cursor': r['cursor']})
          .toList(),
      'nextCursor': rows.length > 50 ? rows[49]['cursor'].toString() : null,
    };
  }

  void retryPending({String? org}) {
    for (final row in database.db.select(
      'SELECT DISTINCT p.order_id FROM billing_pending p JOIN finance_lines l ON l.order_id=p.order_id WHERE (? IS NULL OR l.org_id=?) LIMIT 50',
      [org, org],
    )) {
      sync(finance.order(row['order_id'] as String));
    }
  }

  void queue(String id) => database.db.execute(
    'INSERT INTO billing_pending(order_id,reason,created_at) VALUES(?,?,?) ON CONFLICT(order_id) DO NOTHING',
    [id, 'Spracovanie zmeny objednávky', now],
  );

  int cleanExpired() => database.transaction(() {
    database.db.execute(
      "DELETE FROM billing_documents WHERE retention_until<=? AND order_id IN (SELECT id FROM orders WHERE status IN ('collected','cancelled')) AND NOT EXISTS(SELECT 1 FROM finance_holds h WHERE h.order_id=billing_documents.order_id) AND NOT EXISTS(SELECT 1 FROM support_tickets t WHERE t.order_id=billing_documents.order_id AND t.status NOT IN ('closed','resolved')) AND NOT EXISTS(SELECT 1 FROM billing_documents c WHERE json_extract(c.payload,'\$.originalDocumentId')=billing_documents.id AND c.retention_until>?)",
      [now, now],
    );
    return database.db.updatedRows;
  });

  void validateCheckout(List<OrderItem> items, {required int serviceFee}) {
    if (!config.production) return;
    if (model == null) {
      throw const ApiFailure(
        503,
        'Prevádzkovateľ ešte nedokončil nastavenie dokladov.',
      );
    }
    void validate(String scope, String? key) {
      final p = _issuer(scope);
      if (p['taxMode'] == 'vat' && !(p['rates'] as Map).containsKey(key)) {
        throw const ApiFailure(
          503,
          'Vystavovateľ ešte nedokončil nastavenie daňových sadzieb.',
        );
      }
    }

    if (serviceFee > 0) validate('platform', 'fee');
    for (final item in items) {
      final org =
          database.db.select(
                'SELECT s.org_id FROM merchant_offers m JOIN merchant_stores s ON s.id=m.store_id WHERE m.offer_id=?',
                [item.offerId],
              ).firstOrNull?['org_id']
              as String?;
      final scope = model == 'platformSeller' ? 'platform' : org;
      if (scope == null) {
        throw const ApiFailure(
          503,
          'Ponuka nemá overené nastavenie predávajúceho.',
        );
      }
      validate(scope, item.category?.name);
    }
  }

  void sync(RescueOrder order) {
    if (!order.items.any((i) => i.collected)) return;
    try {
      if (model == null) {
        throw const ApiFailure(
          409,
          'Najprv urč predávajúceho a pravidlá dokladov.',
        );
      }
      for (final line in finance.rows(
        'SELECT * FROM finance_lines WHERE order_id=?',
        [order.id],
      )) {
        final item = order.items.firstWhere(
          (i) => i.offerId == line['offer_id'],
        );
        if (!item.collected) continue;
        final a = finance.allocation(line),
            org = line['org_id'] as String?,
            store = line['store_id'] as String?;
        final offer = database.db.select(
          'SELECT payload FROM offers WHERE id=?',
          [item.offerId],
        ).firstOrNull;
        final category =
            item.category?.name ??
            (offer == null
                ? null
                : database.decode(offer['payload'] as String)['category']
                      as String?);
        for (final kind in ['goods', 'fee']) {
          final scope = kind == 'fee' || model == 'platformSeller'
              ? 'platform'
              : org;
          if (scope == null) {
            throw const ApiFailure(409, 'Ponuka nemá určeného predajcu.');
          }
          final source = 'sale:${order.id}:${item.offerId}:$kind';
          final existing = database.db.select(
            'SELECT id FROM billing_documents WHERE scope=? AND source=?',
            [scope, source],
          );
          if (existing.isEmpty && item.remainingQuantity > 0) {
            final issuer = _issuer(scope), rates = issuer['rates'] as Map;
            final rateKey = kind == 'fee' ? 'fee' : category;
            if (issuer['taxMode'] == 'vat' && !rates.containsKey(rateKey)) {
              throw const ApiFailure(
                409,
                'Chýba schválená sadzba DPH pre obsah dokladu.',
              );
            }
            final rate = issuer['taxMode'] == 'notVat'
                ? 0
                : rates[rateKey] as int;
            final gross = [
              for (var i = item.refundCount; i < item.quantity; i++)
                kind == 'fee'
                    ? a.unitSlice(item.quantity, i, 1).fee
                    : a.unitSlice(item.quantity, i, 1).goodsNet,
            ];
            final total = gross.fold(0, (n, v) => n + v);
            if (total == 0) continue;
            final net = (total * 10000 + (10000 + rate) ~/ 2) ~/ (10000 + rate),
                vat = total - net;
            final taxes = allocateCents(vat, gross);
            final units = [
              for (var i = 0; i < gross.length; i++)
                {
                  'ordinal': item.refundCount + i,
                  'gross': gross[i],
                  'net': gross[i] - taxes[i],
                  'vat': taxes[i],
                  'rateBps': rate,
                },
            ];
            _write(
              scope,
              source,
              'invoice',
              order.id,
              org,
              store,
              issuer,
              order.invoice.toJson(),
              units,
              kind == 'fee' ? 'Služba platformy · ${item.title}' : item.title,
              supplied: tz.TZDateTime.from(
                DateTime.parse(line['collected_at'] as String? ?? now),
                tz.getLocation('Europe/Bratislava'),
              ).toIso8601String().substring(0, 10),
              unitPrice: kind == 'fee' ? null : item.unitPrice,
            );
          }
          final original = database.db.select(
            'SELECT id FROM billing_documents WHERE scope=? AND source=?',
            [scope, source],
          ).firstOrNull;
          if (original == null) continue;
          final invoice = read(original['id'] as String);
          for (final refund in finance.rows(
            "SELECT p.*,r.rowid refund_row,r.id refund_id,r.reason,r.created_at FROM finance_refund_parts p JOIN finance_refunds r ON r.id=p.refund_id WHERE p.line_id=? AND r.status='completed' ORDER BY r.rowid",
            [line['id']],
          )) {
            final start =
                database.db.select(
                      "SELECT COALESCE(SUM(p.quantity),0) n FROM finance_refund_parts p JOIN finance_refunds r ON r.id=p.refund_id WHERE p.line_id=? AND r.status='completed' AND r.rowid<?",
                      [line['id'], refund['refund_row']],
                    ).first['n']
                    as int;
            final end = start + (refund['quantity'] as int);
            final selected = (invoice['units'] as List)
                .cast<Map<String, dynamic>>()
                .where(
                  (u) =>
                      (u['ordinal'] as int) >= start &&
                      (u['ordinal'] as int) < end,
                )
                .toList();
            if (selected.isEmpty) continue;
            _write(
              scope,
              'credit:${refund['refund_id']}:${item.offerId}:$kind',
              'creditNote',
              order.id,
              org,
              store,
              Map<String, dynamic>.from(invoice['issuer'] as Map),
              Map<String, dynamic>.from(invoice['buyer'] as Map),
              selected,
              invoice['title'] as String,
              original: invoice['id'] as String,
              originalNumber: invoice['number'] as String,
              supplied: invoice['supplyDate'] as String,
              reason: refund['reason'] as String,
              unitPrice: invoice['unitPrice'] as int?,
            );
          }
        }
      }
      database.db.execute('DELETE FROM billing_pending WHERE order_id=?', [
        order.id,
      ]);
    } on ApiFailure catch (e) {
      database.db.execute(
        'INSERT INTO billing_pending VALUES(?,?,?) ON CONFLICT(order_id) DO UPDATE SET reason=excluded.reason',
        [order.id, e.message, now],
      );
    }
  }

  Future<Uint8List> pdf(String id) async {
    final d = read(id),
        cached = database.db.select(
          'SELECT pdf,pdf_hash FROM billing_documents WHERE id=?',
          [id],
        ).first;
    if (cached['pdf'] != null) {
      final bytes = cached['pdf'] as Uint8List;
      if (sha256.convert(bytes).toString() != cached['pdf_hash']) {
        throw const ApiFailure(503, 'PDF doklad potrebuje kontrolu integrity.');
      }
      return bytes;
    }
    final font = pw.Font.ttf(
      (await File(config.billingFontPath).readAsBytes()).buffer.asByteData(),
    );
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
      title: '${d['number']}',
      author: (d['issuer'] as Map)['name'] as String,
    );
    final issuer = d['issuer'] as Map,
        buyer = d['buyer'] as Map,
        blue = PdfColor.fromInt(0xff1765e8);
    String money(int v) =>
        '${(v / 100).toStringAsFixed(2).replaceAll('.', ',')} EUR';
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (c) => pw.Column(
          children: [
            pw.Divider(color: PdfColors.grey300),
            pw.Text(
              'Save Food · ${d['number']} · ${c.pageNumber}/${c.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'SHA-256: ${d['hash']}',
              style: const pw.TextStyle(fontSize: 6),
            ),
          ],
        ),
        build: (c) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Save Food',
                style: pw.TextStyle(color: blue, fontSize: 24),
              ),
              pw.Text(
                d['kind'] == 'creditNote' ? 'OPRAVNÁ FAKTÚRA' : 'FAKTÚRA',
                style: const pw.TextStyle(fontSize: 18),
              ),
            ],
          ),
          if (d['demo'] == true)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 16),
              padding: const pw.EdgeInsets.all(12),
              color: PdfColors.blue50,
              child: pw.Text(
                'DEMO · Fiktívne údaje. Doklad nie je určený na účtovanie.',
              ),
            ),
          pw.SizedBox(height: 22),
          pw.Text(
            d['number'] as String,
            style: const pw.TextStyle(fontSize: 22),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Vystavené: ${d['issuedAt']}    Dodanie: ${d['supplyDate']}'),
          if (d['originalNumber'] != null)
            pw.Text('Oprava dokladu: ${d['originalNumber']}'),
          if (d['reason'] != null) pw.Text('Dôvod opravy: ${d['reason']}'),
          pw.SizedBox(height: 24),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'DODÁVATEĽ',
                      style: pw.TextStyle(color: blue, fontSize: 10),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(issuer['name'] as String),
                    pw.Text(issuer['address'] as String),
                    pw.Text(
                      '${issuer['country']} · IČO ${issuer['companyId']}',
                    ),
                    if ((issuer['taxId'] as String).isNotEmpty)
                      pw.Text('DIČ ${issuer['taxId']}'),
                    if ((issuer['vatId'] as String).isNotEmpty)
                      pw.Text('IČ DPH ${issuer['vatId']}'),
                    pw.Text(issuer['contactEmail'] as String),
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'ODBERATEĽ',
                      style: pw.TextStyle(color: blue, fontSize: 10),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      (buyer['company'] as String? ?? '').isNotEmpty
                          ? buyer['company'] as String
                          : buyer['name'] as String? ?? '',
                    ),
                    pw.Text(
                      '${buyer['street'] ?? ''}\n${buyer['postcode'] ?? ''} ${buyer['city'] ?? ''}\n${buyer['country'] ?? ''}',
                    ),
                    if ((buyer['companyId'] as String? ?? '').isNotEmpty)
                      pw.Text('IČO ${buyer['companyId']}'),
                    if ((buyer['vatId'] as String? ?? '').isNotEmpty)
                      pw.Text('IČ DPH ${buyer['vatId']}'),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 28),
          pw.TableHelper.fromTextArray(
            headers: ['Obsah', 'Množstvo', 'Základ', 'DPH', 'Spolu'],
            data: [
              [
                d['title'],
                '${d['quantity']} ks',
                money(d['net'] as int),
                money(d['vat'] as int),
                money(d['gross'] as int),
              ],
            ],
            headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: blue),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.all(8),
          ),
          pw.SizedBox(height: 12),
          if (d['unitPrice'] != null)
            pw.Text(
              'Cena za kus pred zľavami: ${money(d['unitPrice'] as int)}. Celková zľava: ${money((d['unitPrice'] as int) * (d['quantity'] as int) - (d['gross'] as int).abs())}.',
            ),
          pw.SizedBox(height: 8),
          for (final rate
              in (d['units'] as List).map((u) => u['rateBps'] as int).toSet())
            pw.Text('Sadzba DPH: ${(rate / 100).toStringAsFixed(2)} %'),
          if (issuer['taxMode'] == 'notVat')
            pw.Text('Dodávateľ nie je platiteľom DPH.'),
          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Celkom ${money(d['gross'] as int)}',
              style: pw.TextStyle(fontSize: 20, color: blue),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Uhradené v aplikácii. Prípadná refundácia sa riadi samostatným opravným dokladom.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
    final bytes = await document.save();
    database.db.execute(
      'UPDATE billing_documents SET pdf=?,pdf_hash=? WHERE id=? AND pdf IS NULL',
      [bytes, sha256.convert(bytes).toString(), id],
    );
    return database.db.select('SELECT pdf FROM billing_documents WHERE id=?', [
          id,
        ]).first['pdf']
        as Uint8List;
  }
}
