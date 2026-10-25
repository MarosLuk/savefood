part of 'server.dart';

extension _PlatformRoutes on MarketplaceServer {
  void _platformRoutes(Router router) {
    router.get(
      '/v1/platform/overview',
      (Request r) => _json(platform.overview(_user(r))),
    );
    router.get(
      '/v1/platform/resources/<kind>',
      (Request r, String kind) =>
          _json(platform.list(_user(r), kind, r.url.queryParameters)),
    );
    router.post(
      '/v1/platform/resources/<kind>/<id>',
      (Request r, String kind, String id) => _merchantMutation(
        r,
        (user, body) => platform.change(user, kind, id, body),
      ),
    );
  }
}
