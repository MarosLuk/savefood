import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('local snapshot roundtrips and can be cleared', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await LocalMarketplaceRepository.open();
    await repo.save({'schema': 1, 'theme': 'dark', 'orders': []});
    expect((await repo.load())!['theme'], 'dark');
    await repo.clear();
    expect(await repo.load(), isNull);
  });
  test('corrupt data is reported, never silently overwritten', () async {
    SharedPreferences.setMockInitialValues({
      LocalMarketplaceRepository.storageKey: 'not json',
    });
    final repo = await LocalMarketplaceRepository.open();
    await expectLater(repo.load(), throwsFormatException);
  });
  test('unknown schema is rejected', () async {
    SharedPreferences.setMockInitialValues({
      LocalMarketplaceRepository.storageKey: '{"schema":99}',
    });
    final repo = await LocalMarketplaceRepository.open();
    await expectLater(repo.load(), throwsFormatException);
  });
}
