part of 'server.dart';

extension _BillingRoutes on MarketplaceServer {
  void _billingRoutes(Router router) {
    router.post(
      '/v1/merchant/billing/<org>/connectors',
      (Request r, String org) => _merchantMutation(r, (u, b) {
        finance.requireOwner(u, org);
        return billing.createConnector(org, b);
      }, status: 201),
    );
    router.post(
      '/v1/merchant/billing/<org>/connectors/<id>/revoke',
      (Request r, String org, String id) => _merchantMutation(r, (u, b) {
        finance.requireOwner(u, org);
        billing.revokeConnector(org, id);
        return {'ok': true};
      }),
    );
    router.post(
      '/v1/platform/billing/connectors',
      (Request r) => _merchantMutation(r, (u, b) {
        platform.require(u, write: true);
        return billing.createConnector('platform', b);
      }, status: 201),
    );
    router.post(
      '/v1/platform/billing/connectors/<id>/revoke',
      (Request r, String id) => _merchantMutation(r, (u, b) {
        platform.require(u, write: true);
        billing.revokeConnector('platform', id);
        return {'ok': true};
      }),
    );
    router.get(
      '/v1/integrations/accounting',
      (Request r) => _json(billing.accountingPage(r.headers['authorization'])),
    );
    router.post(
      '/v1/integrations/accounting/ack',
      (Request r) async => _json(
        billing.accountingAck(r.headers['authorization'], await _body(r)),
      ),
    );

    void authorize(String user, String id) {
      final row = finance.one(
        'SELECT d.scope,d.order_id,d.org_id,o.user_id FROM billing_documents d JOIN orders o ON o.id=d.order_id WHERE d.id=?',
        [id],
      );
      if (row['user_id'] == user ||
          platform.role(user) == 'admin' ||
          platform.role(user) == 'auditor') {
        return;
      }
      if (row['org_id'] != null && row['scope'] == row['org_id']) {
        finance.requireOwner(user, row['org_id'] as String);
        return;
      }
      throw const ApiFailure(403, 'K dokladu nemáš prístup.');
    }

    router.get('/v1/orders/<id>/documents', (Request r, String id) {
      _ownedOrder(_user(r), id);
      return _json({
        'rows': billing.forOrder(id),
        'pending': database.db.select(
          'SELECT reason FROM billing_pending WHERE order_id=?',
          [id],
        ).firstOrNull?['reason'],
      });
    });
    router.get('/v1/documents/<id>/pdf', (Request r, String id) async {
      authorize(_user(r), id);
      final doc = billing.read(id);
      return Response.ok(
        await billing.pdf(id),
        headers: {
          'content-type': 'application/pdf',
          'content-disposition': 'attachment; filename="${doc['number']}.pdf"',
          'cache-control': 'private, no-store',
          'x-content-type-options': 'nosniff',
        },
      );
    });
    router.get('/v1/merchant/billing/<org>', (Request r, String org) {
      finance.requireOwner(_user(r), org);
      return _json({
        'profile': billing.profile(org),
        'model': billing.model,
        'connectors': billing.connectors(org),
      });
    });
    router.post(
      '/v1/merchant/billing/<org>',
      (Request r, String org) => _merchantMutation(r, (u, b) {
        finance.requireOwner(u, org);
        final result = billing.saveProfile(org, b);
        billing.retryPending(org: org);
        return result;
      }),
    );
    router.get('/v1/merchant/documents/<org>', (Request r, String org) {
      finance.requireOwner(_user(r), org);
      return _json(billing.page(org, r.url.queryParameters));
    });
    router.get('/v1/platform/billing', (Request r) {
      platform.require(_user(r));
      return _json({
        'profile': billing.profile('platform'),
        'connectors': billing.connectors('platform'),
        'model': billing.model,
      });
    });
    router.post(
      '/v1/platform/billing',
      (Request r) => _merchantMutation(r, (u, b) {
        platform.require(u, write: true);
        if (b['model'] != null) billing.setModel(stringField(b, 'model'));
        final result = billing.saveProfile('platform', b);
        billing.retryPending();
        return result;
      }),
    );
    router.get('/v1/platform/documents', (Request r) {
      platform.require(_user(r));
      return _json(billing.page(null, r.url.queryParameters));
    });
  }
}
