import 'dart:convert';
import 'package:http/http.dart' as http;

/// Photon /api endpoint, which can be self-hosted for production traffic.
class PlaceSearch {
  PlaceSearch(this.url, {http.Client? client})
    : client = client ?? http.Client();
  final String url;
  final http.Client client;
  final _cache =
      <String, ({DateTime until, List<Map<String, dynamic>> places})>{};
  Future<List<Map<String, dynamic>>> search(
    String query,
    String language,
  ) async {
    if (url.isEmpty || query.length < 3) return [];
    final key = '$language:$query';
    final previous = _cache[key];
    if (previous != null && previous.until.isAfter(DateTime.now())) {
      return previous.places;
    }
    final uri = Uri.parse(url).replace(
      queryParameters: {
        'q': query,
        'lang': language == 'en' ? 'en' : 'default',
        'limit': '6',
      },
    );
    final response = await client
        .get(uri, headers: {'User-Agent': 'com.dakoty.savefood/1.0'})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Place search unavailable');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final places = <Map<String, dynamic>>[];
    for (final raw in (json['features'] as List? ?? [])) {
      final feature = raw as Map, properties = feature['properties'] as Map;
      final coordinates = (feature['geometry'] as Map)['coordinates'] as List;
      if (coordinates.length < 2 ||
          coordinates[0] is! num ||
          coordinates[1] is! num) {
        continue;
      }
      final lon = (coordinates[0] as num).toDouble(),
          lat = (coordinates[1] as num).toDouble();
      if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
        continue;
      }
      final street = [
        properties['street'],
        properties['housenumber'],
      ].whereType<String>().join(' ');
      final label = [
        properties['name'],
        if (street.isNotEmpty) street,
        properties['city'] ?? properties['county'],
        properties['country'],
      ].whereType<String>().where((v) => v.isNotEmpty).toSet().join(', ');
      if (label.isNotEmpty) {
        places.add({
          'label': label,
          'point': {'lat': lat, 'lng': lon},
        });
      }
    }
    if (_cache.length >= 256) _cache.remove(_cache.keys.first);
    _cache[key] = (
      until: DateTime.now().add(const Duration(minutes: 10)),
      places: places,
    );
    return places;
  }

  void close() => client.close();
}
