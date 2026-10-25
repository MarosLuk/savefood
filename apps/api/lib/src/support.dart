import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:uuid/uuid.dart';
import 'auth.dart';
import 'database.dart';
import 'push.dart';
import 'image_codec.dart';
import 'mail.dart';

part 'support_activity.dart';
part 'support_photos.dart';

class SupportService {
  SupportService(this.database, {DateTime Function()? clock, this.mail})
    : clock = clock ?? DateTime.now {
    database.db.execute('''
      CREATE TABLE IF NOT EXISTS support_agents(user_id TEXT PRIMARY KEY REFERENCES users(id),active INTEGER NOT NULL DEFAULT 1);
      CREATE TABLE IF NOT EXISTS support_tickets(id TEXT PRIMARY KEY,number INTEGER NOT NULL UNIQUE,
        user_id TEXT NOT NULL REFERENCES users(id),order_id TEXT REFERENCES orders(id),subject TEXT NOT NULL,
        category TEXT NOT NULL,status TEXT NOT NULL,priority TEXT NOT NULL,assignee TEXT REFERENCES users(id),
        source_key TEXT UNIQUE,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1);
      CREATE INDEX IF NOT EXISTS support_tickets_user ON support_tickets(user_id,updated_at);
      CREATE TABLE IF NOT EXISTS support_messages(id TEXT PRIMARY KEY,ticket_id TEXT NOT NULL REFERENCES support_tickets(id),
        user_id TEXT REFERENCES users(id),author TEXT NOT NULL,body TEXT NOT NULL,internal INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS support_messages_ticket ON support_messages(ticket_id,created_at);
      CREATE TABLE IF NOT EXISTS support_audit(id TEXT PRIMARY KEY,ticket_id TEXT NOT NULL REFERENCES support_tickets(id),
        actor TEXT NOT NULL,event TEXT NOT NULL,detail TEXT NOT NULL,created_at TEXT NOT NULL);
    ''');
    initializeActivity();
    initializePhotos();
    if (!rows(
      'PRAGMA table_info(support_tickets)',
    ).any((r) => r['name'] == 'search')) {
      database.db.execute(
        "ALTER TABLE support_tickets ADD COLUMN search TEXT NOT NULL DEFAULT ''",
      );
    }
    for (final t in rows(
      "SELECT id,number,subject,order_id FROM support_tickets WHERE search=''",
    )) {
      _index(
        t['id'] as String,
        t['number'] as int,
        t['subject'] as String,
        t['order_id'] as String?,
      );
    }
  }
  final MarketplaceDatabase database;
  final MailService? mail;
  int photoDecodes = 0;
  final DateTime Function() clock;
  String get now => clock().toUtc().toIso8601String();
  List<Map<String, dynamic>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) => database.db
      .select(sql, args)
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  bool isAgent(String user) => rows(
    'SELECT user_id FROM support_agents WHERE user_id=? AND active=1',
    [user],
  ).isNotEmpty;
  void requireAgent(String user) {
    if (!isAgent(user)) {
      throw const ApiFailure(403, 'Táto časť je dostupná zákazníckej podpore.');
    }
  }

  void operation(String user, String id, String event, String detail) {
    requireAgent(user);
    _owned(user, id);
    _audit(id, user, event, detail);
  }

  void setAgent(String email, bool enabled) {
    final user = rows('SELECT id FROM users WHERE email=?', [
      email.toLowerCase(),
    ]).firstOrNull;
    if (user == null) {
      throw const ApiFailure(404, 'Používateľ s týmto účtom sa nenašiel.');
    }
    database.db.execute(
      'INSERT INTO support_agents VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET active=excluded.active',
      [user['id'], enabled ? 1 : 0],
    );
  }

  Map<String, dynamic> _owned(String user, String id) {
    final t = rows('SELECT * FROM support_tickets WHERE id=?', [
      id,
    ]).firstOrNull;
    if (t == null || t['user_id'] != user && !isAgent(user)) {
      throw const ApiFailure(404, 'Požiadavka sa nenašla.');
    }
    return t;
  }

  void _index(String id, int number, String subject, String? order) =>
      database.db.execute('UPDATE support_tickets SET search=? WHERE id=?', [
        normalizeSearch(
          'NVP-${number.toString().padLeft(5, '0')} $subject ${order ?? ''}',
        ),
        id,
      ]);

  Map<String, dynamic> ticket(
    String user,
    String id, {
    int? before,
    int? after,
  }) {
    if (before != null && after != null) {
      throw const ApiFailure(400, 'Vyber jeden smer histórie.');
    }
    final t = _owned(user, id), agent = isAgent(user);
    final page = rows(
      "SELECT m.*,m.rowid n FROM support_messages m WHERE ticket_id=? AND (?=1 OR internal=0) AND (? IS NULL OR m.rowid<?) AND (? IS NULL OR m.rowid>?) ORDER BY m.rowid ${after == null ? 'DESC' : 'ASC'} LIMIT 51",
      [id, agent ? 1 : 0, before, before, after, after],
    );
    final messages = after == null
        ? page.take(50).toList().reversed.toList()
        : page.take(50).toList();
    final actor = t['assignee'] == null
        ? null
        : rows('SELECT name FROM users WHERE id=?', [
            t['assignee'],
          ]).firstOrNull;
    return {
      'id': id,
      'number': 'NVP-${(t['number'] as int).toString().padLeft(5, '0')}',
      'orderId': t['order_id'],
      'subject': t['subject'],
      'category': t['category'],
      'status': t['status'],
      'priority': t['priority'],
      'assignee': agent ? t['assignee'] : null,
      'assigneeName': agent ? (actor?['name']) : null,
      'canManage': agent,
      'version': t['version'],
      'createdAt': t['created_at'],
      'updatedAt': t['updated_at'],
      'unread': rows(
        'SELECT id FROM support_notifications WHERE user_id=? AND ticket_id=? AND read_at IS NULL LIMIT 1',
        [user, id],
      ).isNotEmpty,
      'nextMessagesCursor': after == null && page.length > 50
          ? messages.first['n']
          : null,
      'hasMoreMessages': after != null && page.length > 50,
      'draftAttachments': rows(
        'SELECT id,width,height,length(content) size FROM support_photos WHERE ticket_id=? AND user_id=? AND message_id IS NULL ORDER BY rowid',
        [id, user],
      ).map(_photoInfo).toList(),
      'lastMessageCursor': messages.lastOrNull?['n'] ?? 0,
      'messages': messages
          .map(
            (m) => {
              'id': m['id'],
              'cursor': m['n'],
              'author': m['author'],
              'body': m['body'],
              'internal': m['internal'] == 1,
              'createdAt': m['created_at'],
              'attachments': photoMetadata(m['id'] as String),
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> list(
    String user, {
    bool inbox = false,
    String? status,
    int? before,
    String? search,
    String? priority,
    String assignment = 'all',
    bool unread = false,
  }) {
    if (inbox) requireAgent(user);
    if (status != null && !TicketStatus.values.any((v) => v.name == status)) {
      throw const ApiFailure(400, 'Neplatný stav požiadavky.');
    }
    if (priority != null && !{'normal', 'urgent'}.contains(priority) ||
        !{'all', 'mine', 'unassigned'}.contains(assignment)) {
      throw const ApiFailure(400, 'Neplatný filter.');
    }
    if (!inbox && assignment != 'all') {
      throw const ApiFailure(403, 'Priradenie je dostupné operátorom.');
    }
    final query = normalizeSearch(search ?? '');
    if (query.length > 150) {
      throw const ApiFailure(400, 'Vyhľadávanie je príliš dlhé.');
    }
    final records = rows(
      """SELECT t.*,t.rowid n FROM support_tickets t WHERE (?=1 OR user_id=?) AND (? IS NULL OR status=?) AND (? IS NULL OR t.rowid<?)
      AND instr(t.search,?)>0 AND (? IS NULL OR priority=?) AND (?='all' OR (?='mine' AND assignee=?) OR (?='unassigned' AND assignee IS NULL))
      AND (?=0 OR EXISTS(SELECT 1 FROM support_notifications n WHERE n.ticket_id=t.id AND n.user_id=? AND n.read_at IS NULL))
      ORDER BY t.rowid DESC LIMIT 51""",
      [
        inbox ? 1 : 0,
        user,
        status,
        status,
        before,
        before,
        query,
        priority,
        priority,
        assignment,
        assignment,
        user,
        assignment,
        unread ? 1 : 0,
        user,
      ],
    );
    final page = records.take(50).toList();
    return {
      'isAgent': isAgent(user),
      'tickets': page.map((t) {
        final j = ticket(user, t['id'] as String);
        j['messages'] = [];
        return j;
      }).toList(),
      'nextCursor': records.length > 50 ? page.last['n'] : null,
    };
  }

  Map<String, dynamic> auditPage(String user, String id, {int? before}) {
    requireAgent(user);
    _owned(user, id);
    final all = rows(
      'SELECT a.rowid cursor,a.event,a.detail,a.created_at,u.name actor FROM support_audit a LEFT JOIN users u ON u.id=a.actor WHERE ticket_id=? AND (? IS NULL OR a.rowid<?) ORDER BY a.rowid DESC LIMIT 51',
      [id, before, before],
    );
    final page = all.take(50).toList();
    return {
      'events': page,
      'nextCursor': all.length > 50 ? page.last['cursor'] : null,
    };
  }

  Map<String, dynamic> agents(String user) {
    requireAgent(user);
    return {
      'agents': rows(
        'SELECT u.id,u.name FROM support_agents a JOIN users u ON u.id=a.user_id WHERE a.active=1 ORDER BY u.name',
      ),
    };
  }

  Map<String, dynamic> create(
    String user,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final subject = stringField(b, 'subject', max: 150),
        message = stringField(b, 'message', max: 5000);
    final category = TicketCategory.values.byName(stringField(b, 'category'));
    final orderId = b['orderId'] as String?;
    if (subject.length < 3 || message.length < 3) {
      throw const ApiFailure(400, 'Vyplň predmet a správu aspoň tromi znakmi.');
    }
    RescueOrder? order;
    if (orderId != null) {
      final r = rows('SELECT payload FROM orders WHERE id=? AND user_id=?', [
        orderId,
        user,
      ]).firstOrNull;
      if (r == null) throw const ApiFailure(404, 'Objednávka sa nenašla.');
      order = RescueOrder.fromJson(database.decode(r['payload'] as String));
    }
    final id = _create(user, orderId, subject, category, message);
    _message(id, null, 'assistant', _answer(category, order));
    return ticket(user, id);
  });
  String _create(
    String user,
    String? order,
    String subject,
    TicketCategory category,
    String message, {
    String? source,
  }) {
    final id = const Uuid().v4();
    final number =
        (rows(
              'SELECT COALESCE(MAX(number),0) n FROM support_tickets',
            ).first['n']
            as int) +
        1;
    final urgent = category == TicketCategory.foodQuality;
    database.db.execute(
      'INSERT INTO support_tickets(id,number,user_id,order_id,subject,category,status,priority,source_key,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        number,
        user,
        order,
        subject,
        category.name,
        'open',
        urgent ? 'urgent' : 'normal',
        source,
        now,
        now,
      ],
    );
    _index(id, number, subject, order);
    _message(id, user, 'customer', message);
    _audit(id, user, 'created', category.name);
    return id;
  }

  String _answer(TicketCategory c, RescueOrder? order) {
    final state = order == null
        ? ''
        : ' Objednávka ${order.id.substring(0, mathMin(8, order.id.length)).toUpperCase()} je ${switch (order.status) {
            OrderStatus.awaitingPayment => 'v stave čakania na platbu',
            OrderStatus.reserved => 'pripravená na vyzdvihnutie',
            OrderStatus.collected => 'vyzdvihnutá',
            OrderStatus.cancelled => 'zrušená',
          }}.';
    return switch (c) {
      TicketCategory.payment =>
        'Automatický asistent: požiadavku sme prijali.$state Stav platby môžeš obnoviť v detaile objednávky. Neposielaj číslo karty ani overovacie kódy. Ak problém trvá, dopíš podrobnosti sem.',
      TicketCategory.pickup =>
        'Automatický asistent: čas, adresu a kód nájdeš v detaile objednávky.$state Ak je prevádzka zatvorená alebo balíček chýba, napíš nám sem; prípad prevezme podpora.',
      TicketCategory.cancellation =>
        'Automatický asistent: pred začiatkom výdaja môžeš rezerváciu zrušiť v jej detaile.$state Ak ide o časť objednávky alebo už vyzdvihnutý balíček, reklamáciu posúdi podpora a výsledok uvidíš v tejto konverzácii.',
      TicketCategory.foodQuality =>
        'Automatický asistent: reklamáciu kvality sme označili ako naliehavú. Uveď prevádzku, názov potraviny, šaržu alebo dátum uvedený na obale a opíš problém. Prípad prevezme operátor; táto správa nepotvrdzuje schválenie refundácie.',
      TicketCategory.merchant =>
        'Automatický asistent: v správe uveď prevádzku, SKU alebo identifikátor balíčka a čo potrebuješ upraviť. Prístupy ani tajné integračné tokeny neposielaj. Ozve sa ti podpora.',
      TicketCategory.other =>
        'Automatický asistent: správu sme prijali. Balíček s prekvapením má meniaci sa obsah; fotografia je ilustračná. Podpora si prečíta tvoju otázku a odpovie v tejto konverzácii.',
    };
  }

  int mathMin(int a, int b) => a < b ? a : b;
  String _message(
    String id,
    String? user,
    String author,
    String body, {
    bool internal = false,
  }) {
    final message = _id();
    database.db.execute('INSERT INTO support_messages VALUES(?,?,?,?,?,?,?)', [
      message,
      id,
      user,
      author,
      body,
      internal ? 1 : 0,
      now,
    ]);
    messageActivity(id, message, user, author, internal);
    return message;
  }

  String _id() => const Uuid().v4();
  void _audit(String id, String user, String event, String detail) =>
      database.db.execute('INSERT INTO support_audit VALUES(?,?,?,?,?,?)', [
        const Uuid().v4(),
        id,
        user,
        event,
        detail,
        now,
      ]);
  Map<String, dynamic> reply(
    String user,
    String id,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final t = _owned(user, id),
        agent = isAgent(user),
        message = stringField(b, 'message', max: 5000);
    final internal = b['internal'] == true;
    if (internal && !agent) {
      throw const ApiFailure(403, 'Interné poznámky môže pridávať podpora.');
    }
    final attachments = (b['attachments'] as List? ?? []).cast<String>();
    if (message.isEmpty && attachments.isEmpty) {
      throw const ApiFailure(400, 'Napíš správu alebo prilož fotografiu.');
    }
    validatePhotos(user, id, attachments);
    final messageId = _message(
      id,
      user,
      agent ? 'agent' : 'customer',
      message,
      internal: internal,
    );
    linkPhotos(messageId, attachments);
    final status = agent
        ? (internal ? t['status'] : 'waitingCustomer')
        : 'open';
    database.db.execute(
      'UPDATE support_tickets SET status=?,updated_at=?,version=version+1 WHERE id=?',
      [status, now, id],
    );
    return ticket(user, id);
  });
  Map<String, dynamic> update(
    String user,
    String id,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    requireAgent(user);
    final t = _owned(user, id);
    if (b['expectedVersion'] != t['version']) {
      throw const ApiFailure(
        409,
        'Požiadavku medzitým upravil kolega. Obnov ju.',
      );
    }
    final status = TicketStatus.values.byName(stringField(b, 'status'));
    final priority = stringField(b, 'priority');
    if (!{'normal', 'urgent'}.contains(priority)) {
      throw const ApiFailure(400, 'Neplatná priorita.');
    }
    final assignee = b['assignToMe'] == true
        ? user
        : b.containsKey('assigneeId')
        ? b['assigneeId'] as String?
        : t['assignee'];
    if (assignee != null && !isAgent(assignee as String)) {
      throw const ApiFailure(409, 'Vybraný operátor už nemá prístup.');
    }
    database.db.execute(
      'UPDATE support_tickets SET status=?,priority=?,assignee=?,updated_at=?,version=version+1 WHERE id=?',
      [status.name, priority, assignee, now, id],
    );
    _audit(
      id,
      user,
      'updated',
      '${status.name}; $priority; ${assignee ?? "nepriradené"}',
    );
    if (status.name != t['status']) {
      _message(
        id,
        user,
        'agent',
        'Stav požiadavky: ${switch (status) {
          TicketStatus.open => "Nová požiadavka",
          TicketStatus.inProgress => "Riešime",
          TicketStatus.waitingCustomer => "Čakáme na tvoju odpoveď",
          TicketStatus.resolved => "Vyriešené",
          TicketStatus.closed => "Uzavreté",
        }}.',
      );
    }
    return ticket(user, id);
  });
  void closeByCustomer(String user, String id) => database.transaction(() {
    final t = _owned(user, id);
    if (t['user_id'] != user) {
      throw const ApiFailure(403, 'Túto akciu vykoná zákazník.');
    }
    database.db.execute(
      "UPDATE support_tickets SET status='closed',updated_at=?,version=version+1 WHERE id=?",
      [now, id],
    );
    _audit(id, user, 'closed', 'Zákazník potvrdil vyriešenie.');
    _message(id, user, 'customer', 'Zákazník označil problém za vyriešený.');
  });
  void systemTicket(
    String user,
    String order,
    TicketCategory category,
    String source,
    String subject,
    String message,
  ) => database.transaction(() {
    if (rows('SELECT id FROM support_tickets WHERE source_key=?', [
      source,
    ]).isNotEmpty) {
      return;
    }
    final id = _create(user, order, subject, category, message, source: source);
    _message(
      id,
      null,
      'assistant',
      'Automatická kontrola: udalosť sme zaznamenali a zaradili na preverenie podpory. Stav môžeš sledovať v tejto konverzácii.',
    );
  });
  void refundNote(
    String user,
    String id,
    String refund,
  ) => database.transaction(() {
    requireAgent(user);
    _owned(user, id);
    if (rows(
      "SELECT id FROM support_audit WHERE ticket_id=? AND event='refund' AND detail=?",
      [id, refund],
    ).isNotEmpty) {
      return;
    }
    _message(
      id,
      user,
      'agent',
      'Refundácia položiek bola dokončená. Identifikátor: $refund. Platba sa vracia pôvodným spôsobom a použitý kredit do peňaženky.',
    );
    database.db.execute(
      "UPDATE support_tickets SET status='resolved',updated_at=?,version=version+1 WHERE id=?",
      [now, id],
    );
    _audit(id, user, 'refund', refund);
  });
}
