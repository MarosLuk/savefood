part of 'server.dart';

extension _OperationsRoutes on MarketplaceServer {
  void _operationsRoutes(Router router) {
    router.get(
      '/v1/merchant/finance/<org>',
      (Request r, String org) => _json(finance.summary(_user(r), org)),
    );
    router.post(
      '/v1/merchant/finance/<org>/connect',
      (Request r, String org) async =>
          _json(await finance.connect(_user(r), org, link: true)),
    );
    router.post(
      '/v1/merchant/finance/<org>/refresh',
      (Request r, String org) async =>
          _json(await finance.connect(_user(r), org)),
    );
    router.post(
      '/v1/merchant/finance/<org>/automatic',
      (Request r, String org) => _merchantMutation(r, (u, b) {
        if (b['enabled'] is! bool) {
          throw const ApiFailure(400, 'Vyber zapnutie alebo vypnutie.');
        }
        finance.automatic(u, org, b['enabled'] as bool);
        return {'ok': true};
      }),
    );
    router.post('/v1/merchant/finance/<org>/settle', (
      Request r,
      String org,
    ) async {
      final response = await _merchantMutation(
        r,
        (u, b) => {'queued': finance.queue(u, org)},
      );
      unawaited(finance.drain());
      return response;
    });
    router.get(
      '/v1/merchant/finance/<org>/export',
      (Request r, String org) => _json(
        finance.export(
          _user(r),
          org,
          r.url.queryParameters['from'],
          r.url.queryParameters['to'],
        ),
      ),
    );
    router.get(
      '/v1/support/tickets',
      (Request r) => _json(
        support.list(
          _user(r),
          inbox: r.url.queryParameters['inbox'] == 'true',
          status: r.url.queryParameters['status'],
          before: int.tryParse(r.url.queryParameters['before'] ?? ''),
          search: r.url.queryParameters['search'],
          priority: r.url.queryParameters['priority'],
          assignment: r.url.queryParameters['assignment'] ?? 'all',
          unread: r.url.queryParameters['unread'] == 'true',
        ),
      ),
    );
    router.post(
      '/v1/support/tickets',
      (Request r) =>
          _merchantMutation(r, (u, b) => support.create(u, b), status: 201),
    );
    router.get(
      '/v1/support/tickets/<id>',
      (Request r, String id) => _json(
        support.ticket(
          _user(r),
          id,
          before: int.tryParse(r.url.queryParameters['before'] ?? ''),
          after: int.tryParse(r.url.queryParameters['after'] ?? ''),
        ),
      ),
    );
    router.get(
      '/v1/support/agents',
      (Request r) => _json(support.agents(_user(r))),
    );
    router.post(
      '/v1/support/photos/<id>/discard',
      (Request r, String id) => _merchantMutation(r, (u, b) {
        support.discardPhoto(u, id);
        return {'ok': true};
      }),
    );
    router.get(
      '/v1/support/tickets/<id>/audit',
      (Request r, String id) => _json(
        support.auditPage(
          _user(r),
          id,
          before: int.tryParse(r.url.queryParameters['before'] ?? ''),
        ),
      ),
    );
    router.get(
      '/v1/support/notifications',
      (Request r) => _json(
        support.activity(
          _user(r),
          before: int.tryParse(r.url.queryParameters['before'] ?? ''),
        ),
      ),
    );
    int readThrough(Map<String, dynamic> b) {
      if (b['through'] is! int || (b['through'] as int) < 0) {
        throw const ApiFailure(400, 'Neplatná pozícia čítania.');
      }
      return b['through'] as int;
    }

    router.post(
      '/v1/support/notifications/read',
      (Request r) => _merchantMutation(r, (u, b) {
        support.readActivity(u, readThrough(b));
        return {'ok': true};
      }),
    );
    router.post(
      '/v1/support/tickets/<id>/read',
      (Request r, String id) => _merchantMutation(r, (u, b) {
        support.readTicket(u, id, readThrough(b));
        return {'ok': true};
      }),
    );
    router.post('/v1/support/tickets/<id>/photos', (
      Request r,
      String id,
    ) async {
      final user = _user(r);
      support.ticket(user, id);
      final data = BytesBuilder(copy: false);
      await for (final chunk in r.read()) {
        if (data.length + chunk.length > 5 * 1024 * 1024) {
          throw const ApiFailure(413, 'Fotografia môže mať najviac 5 MB.');
        }
        data.add(chunk);
      }
      return _json(
        await support.addPhoto(user, id, data.takeBytes()),
        status: 201,
      );
    });
    router.get(
      '/v1/support/photos/<id>',
      (Request r, String id) => Response.ok(
        support.photo(_user(r), id),
        headers: {
          'content-type': 'image/jpeg',
          'cache-control': 'private, no-store',
          'content-disposition': 'inline; filename="priloha.jpg"',
        },
      ),
    );
    router.post(
      '/v1/support/tickets/<id>/messages',
      (Request r, String id) =>
          _merchantMutation(r, (u, b) => support.reply(u, id, b), status: 201),
    );
    router.post(
      '/v1/support/tickets/<id>/status',
      (Request r, String id) =>
          _merchantMutation(r, (u, b) => support.update(u, id, b)),
    );
    router.post(
      '/v1/support/tickets/<id>/close',
      (Request r, String id) => _merchantMutation(r, (u, b) {
        support.closeByCustomer(u, id);
        return {'ok': true};
      }),
    );
    router.get('/v1/support/tickets/<id>/order', (Request r, String id) {
      final user = _user(r);
      support.requireAgent(user);
      final t = support.ticket(user, id);
      if (t['orderId'] == null) {
        throw const ApiFailure(404, 'Požiadavka nie je spojená s objednávkou.');
      }
      final o = finance.order(t['orderId'] as String);
      return _json({
        'id': o.id,
        'status': o.status.name,
        'total': o.total,
        'refundedAmount': o.refundedAmount,
        'items': o.items
            .map(
              (i) => {
                ...i.toJson(),
                ...finance
                    .allocation(
                      finance.one(
                        'SELECT * FROM finance_lines WHERE order_id=? AND offer_id=?',
                        [o.id, i.offerId],
                      ),
                    )
                    .toJson(),
              },
            )
            .toList(),
        'transfers': finance.rows(
          'SELECT t.id,t.status,t.amount,t.provider_id,t.error FROM finance_transfers t JOIN finance_lines l ON l.id=t.line_id WHERE l.order_id=?',
          [o.id],
        ),
        'reversals': finance.rows(
          'SELECT r.refund_id,r.transfer_id,r.amount,r.status,r.attempted_at FROM finance_reversals r JOIN finance_refunds f ON f.id=r.refund_id WHERE f.order_id=?',
          [o.id],
        ),
        'refunds': finance.rows(
          'SELECT id,offer_ids,status,external,credit,error FROM finance_refunds WHERE order_id=?',
          [o.id],
        ),
      });
    });
    router.post('/v1/support/tickets/<id>/refund', (
      Request r,
      String id,
    ) async {
      final user = _user(r);
      support.requireAgent(user);
      final t = support.ticket(user, id), body = await _body(r);
      if (t['orderId'] == null) {
        throw const ApiFailure(409, 'Vyber požiadavku s objednávkou.');
      }
      final result = await finance.refund(
        user,
        t['orderId'] as String,
        body,
        _applyLineRefund,
      );
      support.refundNote(user, id, result['id'] as String);
      billing.sync(finance.order(t['orderId'] as String));
      return _json(result);
    });
    router.post('/v1/support/tickets/<id>/release-finance', (
      Request r,
      String id,
    ) async {
      final user = _user(r);
      support.requireAgent(user);
      final ticket = support.ticket(user, id);
      if (ticket['orderId'] == null) {
        throw const ApiFailure(409, 'Požiadavka nemá objednávku.');
      }
      await finance.clearHold(ticket['orderId'] as String);
      support.operation(
        user,
        id,
        'finance_hold_released',
        ticket['orderId'] as String,
      );
      return _json({'ok': true});
    });
    router.post('/v1/support/tickets/<id>/transfers/<job>/reconcile', (
      Request r,
      String id,
      String job,
    ) async {
      final user = _user(r);
      support.requireAgent(user);
      final ticket = support.ticket(user, id), body = await _body(r);
      finance.one(
        'SELECT t.id FROM finance_transfers t JOIN finance_lines l ON l.id=t.line_id WHERE t.id=? AND l.order_id=?',
        [job, ticket['orderId']],
      );
      await finance.reconcileTransfer(
        job,
        stringField(body, 'providerId', max: 200),
      );
      support.operation(user, id, 'transfer_reconciled', job);
      return _json({'ok': true});
    });
    router.post('/v1/support/tickets/<id>/refunds/<refund>/provider', (
      Request r,
      String id,
      String refund,
    ) async {
      final user = _user(r);
      support.requireAgent(user);
      final ticket = support.ticket(user, id), body = await _body(r);
      finance.one('SELECT id FROM finance_refunds WHERE id=? AND order_id=?', [
        refund,
        ticket['orderId'],
      ]);
      await finance.reconcileUnitRefund(
        refund,
        stringField(body, 'providerId', max: 200),
      );
      support.operation(user, id, 'refund_provider_verified', refund);
      return _json({'verified': true});
    });
    router.post('/v1/support/tickets/<id>/refunds/<refund>/reversals/<job>', (
      Request r,
      String id,
      String refund,
      String job,
    ) async {
      final user = _user(r);
      support.requireAgent(user);
      final ticket = support.ticket(user, id), body = await _body(r);
      finance.one('SELECT id FROM finance_refunds WHERE id=? AND order_id=?', [
        refund,
        ticket['orderId'],
      ]);
      await finance.reconcileUnitReversal(
        refund,
        job,
        stringField(body, 'providerId', max: 200),
      );
      support.operation(user, id, 'refund_reversal_verified', job);
      return _json({'verified': true});
    });
    router.post('/v1/support/tickets/<id>/refunds/<refund>/retry', (
      Request r,
      String id,
      String refund,
    ) async {
      final user = _user(r);
      support.requireAgent(user);
      final ticket = support.ticket(user, id);
      final previous = finance.one(
        'SELECT * FROM finance_refunds WHERE id=? AND order_id=?',
        [refund, ticket['orderId']],
      );
      final result = await finance
          .refund(previous['actor'] as String, previous['order_id'] as String, {
            'idempotencyKey': previous['idempotency'],
            'reason': previous['reason'],
            'offerIds': jsonDecode(previous['offer_ids'] as String),
            if (previous['quantity_request'] == 1)
              'quantities': jsonDecode(previous['quantities'] as String),
          }, _applyLineRefund);
      support.refundNote(user, id, result['id'] as String);
      billing.sync(finance.order(ticket['orderId'] as String));
      return _json(result);
    });
    router.post('/v1/admin/support/agents', (Request r) async {
      _admin(r);
      final b = await _body(r);
      if (b['enabled'] is! bool) {
        throw const ApiFailure(400, 'Vyber oprávnenie.');
      }
      support.setAgent(stringField(b, 'email'), b['enabled'] as bool);
      return _json({'ok': true});
    });
  }

  void _applyLineRefund(
    RescueOrder previous,
    List<String> ids,
    int external,
    int credit,
    String refund,
  ) {
    final quantities = finance.refundQuantities(refund);
    final items = previous.items
        .map(
          (i) => quantities.containsKey(i.offerId)
              ? i.withRefunded(quantities[i.offerId])
              : i,
        )
        .toList();
    merchants.releaseUnits(previous, quantities, refund);
    final complete = items.every((i) => i.collected || i.refunded),
        allRefunded = items.every((i) => i.refunded);
    final payload = previous.toJson()
      ..['items'] = items.map((i) => i.toJson()).toList()
      ..['status'] = allRefunded
          ? OrderStatus.cancelled.name
          : complete
          ? OrderStatus.collected.name
          : OrderStatus.reserved.name
      ..['refundedAmount'] = previous.refundedAmount + external + credit;
    // Before cashback is earned, exclude refunded goods. Earned cashback is kept.
    final earned = database.db.select(
      "SELECT id FROM ledger WHERE order_id=? AND kind='cashback'",
      [previous.id],
    ).isNotEmpty;
    if (!earned && previous.cashback > 0) {
      final remaining = finance
          .rows('SELECT * FROM finance_lines WHERE order_id=?', [previous.id])
          .fold(0, (n, l) {
            final item = items.firstWhere((i) => i.offerId == l['offer_id']);
            return n +
                finance
                    .allocation(l)
                    .unitSlice(
                      item.quantity,
                      item.refundCount,
                      item.remainingQuantity,
                    )
                    .goodsNet;
          });
      payload['cashback'] = (remaining + 5) ~/ 10;
    }
    final updated = RescueOrder.fromJson(payload);
    _writeOrder(updated);
    final user =
        finance.one('SELECT user_id FROM orders WHERE id=?', [
              previous.id,
            ])['user_id']
            as String;
    if (credit > 0) {
      database.db.execute('UPDATE users SET credit=credit+? WHERE id=?', [
        credit,
        user,
      ]);
      _ledger(user, previous.id, 'refund-$refund', credit);
    }
    if (complete && !earned && updated.cashback > 0) {
      database.db.execute('UPDATE users SET credit=credit+? WHERE id=?', [
        updated.cashback,
        user,
      ]);
      _ledger(user, previous.id, 'cashback', updated.cashback);
    }
  }

  void _scanSupportEvents() {
    for (final row in finance.rows(
      "SELECT DISTINCT o.id,o.user_id FROM orders o JOIN stock_reservations r ON r.order_id=o.id JOIN stock_lots l ON l.id=r.lot_id WHERE r.state='held' AND (l.quality!='checked' OR l.deadline<=?)",
      [clock().toUtc().toIso8601String()],
    )) {
      finance.hold(
        row['id'] as String,
        'Rezervovaná šarža potrebuje kontrolu kvality.',
      );
      support.systemTicket(
        row['user_id'] as String,
        row['id'] as String,
        TicketCategory.foodQuality,
        'stock-risk:${row['id']}',
        'Kontrola rezervovaného balíčka',
        'Automatická kontrola našla zmenu spôsobilosti rezervovanej šarže. Podpora preverí ďalší postup.',
      );
    }
  }

  void _seedOperationsDemo() {
    database.db
        .execute('INSERT OR IGNORE INTO users(id,email,name) VALUES(?,?,?)', [
          'showcase-support',
          'support@demo.nevyhadzuj.test',
          'Nina · zákaznícka podpora',
        ]);
    support.setAgent('support@demo.nevyhadzuj.test', true);
    for (final org in finance.rows(
      "SELECT o.id FROM merchant_organizations o JOIN merchant_members m ON m.org_id=o.id WHERE m.user_id IN ('showcase-bakery','showcase-restaurant')",
    )) {
      database.db.execute(
        "INSERT OR IGNORE INTO finance_accounts(org_id,account_id,ready,status,auto_enabled,updated_at) VALUES(?,?,1,'demo',0,?)",
        [
          org['id'],
          'demo_acct_${org['id']}',
          clock().toUtc().toIso8601String(),
        ],
      );
    }
    final o = finance
        .rows(
          "SELECT id FROM orders WHERE user_id='showcase-customer' AND status='collected' ORDER BY rowid DESC LIMIT 1",
        )
        .firstOrNull;
    if (o != null) {
      support.systemTicket(
        'showcase-customer',
        o['id'] as String,
        TicketCategory.foodQuality,
        'demo-quality',
        'Otázka ku kvalite balíčka',
        'Demo reklamácia: pri jednom výrobku potrebujem preveriť označenie dátumu na obale.',
      );
    }
    final active = finance
        .rows(
          "SELECT id FROM orders WHERE user_id='showcase-customer' AND status='reserved' ORDER BY rowid DESC LIMIT 1",
        )
        .firstOrNull;
    if (active != null) {
      support.systemTicket(
        'showcase-customer',
        active['id'] as String,
        TicketCategory.pickup,
        'demo-pickup',
        'Kde nájdem výdajné miesto?',
        'Demo otázka: prosím o overenie adresy a času vyzdvihnutia.',
      );
    }
  }
}

extension _WarehousePresentation on MarketplaceServer {
  Future<void> _seedWarehousePresentation() async {
    final w = merchants.workspace('showcase-bakery');
    final stores = (w['stores'] as List).cast<Map>();
    if (stores.length < 2) return;
    final source = stores.first['id'] as String,
        destination = stores[1]['id'] as String;
    final available = (w['lots'] as List)
        .cast<Map>()
        .where(
          (l) =>
              l['storeId'] == source &&
              l['quality'] == 'checked' &&
              (l['onHand'] as int) - (l['reserved'] as int) > 10 &&
              DateTime.parse(l['deadline'] as String).isAfter(clock()),
        )
        .firstOrNull;
    if (available != null) {
      if (finance
          .rows(
            "SELECT id FROM stock_transfers WHERE reason='DEMO · Zásobenie druhej pobočky'",
          )
          .isEmpty) {
        final t = merchants.createTransfer('showcase-bakery', {
          'lotId': available['id'],
          'destinationStoreId': destination,
          'quantity': 3,
          'reason': 'DEMO · Zásobenie druhej pobočky',
        });
        merchants.updateTransfer('showcase-bakery', t['id'] as String, {
          'version': t['version'],
          'action': 'dispatch',
          'lotVersion': t['lot']['version'],
          'reason': 'DEMO · Tovar je pripravený na príjem',
        });
      }
      if (finance
          .rows(
            "SELECT id FROM stock_transfers WHERE reason='DEMO · Koncept ranného presunu'",
          )
          .isEmpty) {
        merchants.createTransfer('showcase-bakery', {
          'lotId': available['id'],
          'destinationStoreId': destination,
          'quantity': 2,
          'reason': 'DEMO · Koncept ranného presunu',
        });
      }
    }
    if (finance.rows(
      "SELECT id FROM stock_counts WHERE store_id=? AND (reason='DEMO · Priebežná inventúra pekárne' OR status='draft')",
      [source],
    ).isEmpty) {
      final c = merchants.createCount('showcase-bakery', {
        'storeId': source,
        'reason': 'DEMO · Priebežná inventúra pekárne',
      });
      final lines = (c['lines'] as List)
          .take(2)
          .map((l) => {'lotId': l['lot_id'], 'counted': l['on_hand']})
          .toList();
      if (lines.isNotEmpty) {
        merchants.updateCount('showcase-bakery', c['id'] as String, {
          'version': c['version'],
          'action': 'save',
          'lines': lines,
        });
      }
    }
    final quality = finance
        .rows(
          "SELECT id FROM support_tickets WHERE user_id='showcase-customer' AND category='foodQuality' ORDER BY rowid LIMIT 1",
        )
        .firstOrNull;
    if (quality != null) {
      final id = quality['id'] as String;
      const body =
          'DEMO · Prikladám ilustračnú fotografiu balíčka na posúdenie kvality.';
      final photoFile = File('apps/mobile/assets/images/vegetables.jpg');
      if (photoFile.existsSync() &&
          finance.rows(
            'SELECT id FROM support_messages WHERE ticket_id=? AND body=?',
            [id, body],
          ).isEmpty) {
        final p = await support.addPhoto(
          'showcase-customer',
          id,
          photoFile.readAsBytesSync(),
        );
        support.reply('showcase-customer', id, {
          'message': body,
          'attachments': [p['id']],
        });
      }
      const note =
          'DEMO · Interná poznámka: preveriť šaržu a záznam výdaja. Túto poznámku zákazník nevidí.';
      if (finance.rows(
        'SELECT id FROM support_messages WHERE ticket_id=? AND body=?',
        [id, note],
      ).isEmpty) {
        support.reply('showcase-support', id, {
          'message': note,
          'internal': true,
        });
      }
    }
  }
}
