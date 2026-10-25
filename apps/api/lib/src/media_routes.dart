part of 'server.dart';

extension _MediaRoutes on MarketplaceServer {
  Future<Uint8List> _imageBody(Request r) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in r.read()) {
      if (bytes.length + chunk.length > 5 * 1024 * 1024) {
        throw const ApiFailure(413, 'Fotografia môže mať najviac 5 MB.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  void _mediaRoutes(Router router) {
    router.get(
      '/v1/merchant/media',
      (Request r) => _json(
        media.list(
          _user(r),
          r.url.queryParameters['organizationId'] ?? '',
          before: r.url.queryParameters['before'],
        ),
      ),
    );
    router.post('/v1/merchant/media', (Request r) async {
      final user = _user(r);
      auth.rateLimit('media:$user');
      return _json(
        await media.add(
          user,
          await _imageBody(r),
          org: r.url.queryParameters['organizationId'],
        ),
        status: 201,
      );
    });
    router.get('/v1/media/<id>.jpg', (Request r, String id) {
      final user = r.headers['authorization'] == null ? null : _user(r);
      return Response.ok(
        media.photo(id, user: user),
        headers: {
          'content-type': 'image/jpeg',
          'cache-control': 'no-store',
          'content-disposition': 'inline',
          'content-security-policy': "default-src 'none'",
        },
      );
    });
    router.post('/v1/merchant/media/<id>/delete', (Request r, String id) {
      media.remove(_user(r), id);
      return _json({'deleted': true});
    });
  }
}
