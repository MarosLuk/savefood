part of 'server.dart';

extension _AccountRoutes on MarketplaceServer {
  void _accountRoutes(Router router) {
    router.post('/v1/auth/recovery', (Request r) async {
      auth.rateLimit('recovery:${_ip(r)}');
      if (!mail.gateway.configured && !config.demoShowcase) {
        throw const ApiFailure(
          503,
          'Odosielanie e-mailov nie je nakonfigurované.',
        );
      }
      final body = await _body(r);
      if (body['purpose'] != 'reset') {
        throw const ApiFailure(400, 'Neplatný účel.');
      }
      return _json(await accounts.request(body));
    });
    router.post('/v1/auth/recovery/confirm', (Request r) async {
      auth.rateLimit('recovery-confirm:${_ip(r)}');
      return _json(await accounts.confirm(await _body(r)));
    });
    router.post('/v1/account/challenges', (Request r) async {
      if (!mail.gateway.configured && !config.demoShowcase) {
        throw const ApiFailure(
          503,
          'Odosielanie e-mailov nie je nakonfigurované.',
        );
      }
      return _json(
        await accounts.request(
          await _body(r),
          user: _user(r),
          session: r.headers['authorization']!,
        ),
      );
    });
    router.post('/v1/account/challenges/confirm', (Request r) async {
      final user = _user(r);
      auth.rateLimit('account-confirm:$user');
      return _json(
        await accounts.confirm(
          await _body(r),
          user: user,
          session: r.headers['authorization']!,
        ),
      );
    });
    router.post('/v1/account/password', (Request r) async {
      final user = _user(r);
      auth.rateLimit('password:$user');
      await accounts.password(
        user,
        await _body(r),
        r.headers['authorization']!,
      );
      return _json({'changed': true, 'signInRequired': true});
    });
    router.get(
      '/v1/account/export',
      (Request r) => _json(accounts.export(_user(r))),
    );
    router.post('/v1/account/delete', (Request r) async {
      final user = _user(r);
      auth.rateLimit('delete:$user');
      await accounts.erase(user, await _body(r), r.headers['authorization']!);
      return _json({
        'deleted': true,
        'retained':
            'Záznamy dokončených objednávok a finančných operácií sa uchovávajú oddelene podľa retenčnej politiky prevádzkovateľa.',
      });
    });
    if (config.demoShowcase) {
      router.get('/v1/account/demo-mail', (Request r) {
        final user = _user(r);
        return _json({
          'messages': database.db
              .select(
                "SELECT id,recipient,subject,body,created_at FROM mail_outbox WHERE recipient=? OR (user_id=? AND dedupe LIKE 'account:%') ORDER BY rowid DESC LIMIT 20",
                [auth.user(user)['email'], user],
              )
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
        });
      });
    }
  }
}
