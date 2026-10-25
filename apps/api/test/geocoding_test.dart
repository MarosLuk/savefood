import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_server/src/geocoding.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Photon coordinates are decoded, cached and invalid positions ignored',
    () async {
      var requests = 0;
      final search = PlaceSearch(
        'https://geocoder.example.test/api/',
        client: MockClient((r) async {
          requests++;
          expect(r.url.queryParameters['q'], 'Bratislava');
          expect(r.url.queryParameters['lang'], 'default');
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [17.1, 48.15],
                  },
                  'properties': {
                    'name': 'Bratislava',
                    'city': 'Bratislava',
                    'country': 'Slovensko',
                  },
                },
                {
                  'geometry': {
                    'coordinates': [17, 200],
                  },
                  'properties': {'name': 'Invalid'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(search.close);
      final result = await search.search('Bratislava', 'sk');
      expect(result, hasLength(1));
      expect(result.single['label'], 'Bratislava, Slovensko');
      expect((result.single['point'] as Map)['lat'], 48.15);
      await search.search('Bratislava', 'sk');
      expect(requests, 1);
      expect(await search.search('Br', 'sk'), isEmpty);
    },
  );
}
