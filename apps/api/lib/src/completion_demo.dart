part of 'server.dart';

extension _CompletionDemo on MarketplaceServer {
  Future<void> _prepareCompletionDemo() async {
    if (!config.demoShowcase) return;
    billing.prepareDemo();
    for (final row in finance.rows(
      "SELECT id FROM orders WHERE status='collected'",
    )) {
      billing.sync(finance.order(row['id'] as String));
    }
    database.db.execute(
      "UPDATE reviews SET quality=COALESCE(quality,rating),value=COALESCE(value,rating),quantity=COALESCE(quantity,MAX(1,rating-1)),pickup=COALESCE(pickup,5) WHERE user_id LIKE 'showcase-%'",
    );
    final w = merchants.workspace('showcase-bakery'),
        store = (w['stores'] as List).first as Map;
    if (database.db.select(
      "SELECT id FROM stock_products WHERE org_id=? AND sku='DEMO-KG-JABLKA'",
      [store['organizationId']],
    ).isEmpty) {
      final product = merchants.createProduct('showcase-bakery', {
        'organizationId': store['organizationId'],
        'name': 'Jablká na váhu · demo',
        'sku': 'DEMO-KG-JABLKA',
        'category': 'groceries',
        'unit': 'kilogram',
        'unitValue': 199,
        'allergens': 'Bez povinných alergénov podľa označenia',
        'storage': 'ambient',
        'image': 'vegetables',
      });
      merchants.receive('showcase-bakery', {
        'storeId': store['id'],
        'productId': product['id'],
        'lotCode': 'VAHA-DEMO',
        'quantityDisplay': '8,750',
        'deadline': clock()
            .toUtc()
            .add(const Duration(days: 2))
            .toIso8601String(),
        'dateType': 'bestBefore',
        'quality': 'checked',
      });
    }
    final root = [
      'apps/mobile/assets/images',
      '../mobile/assets/images',
      '/app/demo-images',
    ].where((p) => File('$p/bread.jpg').existsSync()).firstOrNull;
    if (root == null) return;
    for (final user in ['showcase-bakery', 'showcase-restaurant']) {
      final workspace = merchants.workspace(user),
          org = (workspace['organizations'] as List).first['id'] as String;
      if (database.db.select(
        "SELECT id FROM media_assets WHERE org_id=? AND kind='product' AND deleted_at IS NULL LIMIT 1",
        [org],
      ).isNotEmpty) {
        continue;
      }
      for (final asset
          in user == 'showcase-bakery'
              ? ['bread', 'bakery']
              : ['meal', 'salad']) {
        await media.add(
          user,
          await File('$root/$asset.jpg').readAsBytes(),
          org: org,
        );
      }
    }
    final collected = finance
        .rows(
          "SELECT id FROM orders WHERE user_id='showcase-customer' AND status='collected' ORDER BY rowid DESC LIMIT 1",
        )
        .firstOrNull;
    if (collected != null) {
      final item = finance.order(collected['id'] as String).items.first,
          own = database.db.select(
            "SELECT comment FROM reviews WHERE user_id='showcase-customer' AND offer_id=?",
            [item.offerId],
          );
      if (database.db.select(
            "SELECT media_id FROM review_media WHERE user_id='showcase-customer' AND offer_id=?",
            [item.offerId],
          ).isEmpty &&
          (own.isEmpty || (own.first['comment'] as String).contains('Demo'))) {
        final photo = await media.add(
          'showcase-customer',
          await File('$root/bread.jpg').readAsBytes(),
          kind: 'review',
        );
        reviews.save('showcase-customer', item.offerId, {
          'rating': 5,
          'comment':
              'Demo hodnotenie: voňavý balíček, milý personál a jednoduché prevzatie. Ilustračná fotografia.',
          'dimensions': {'quality': 5, 'value': 5, 'quantity': 4, 'pickup': 5},
          'attachments': [photo['id']],
        });
      }
    }
  }
}
