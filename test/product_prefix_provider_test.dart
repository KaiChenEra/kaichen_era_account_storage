import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaichen_era_account_storage/kaichen_era_account_storage.dart';

void main() {
  test(
    'productPrefixProvider defaults to lectio for backward compatibility',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(productPrefixProvider), 'lectio');
    },
  );

  test('productPrefixProvider can be overridden by the host app', () {
    final container = ProviderContainer(
      overrides: [productPrefixProvider.overrideWithValue('ariya')],
    );
    addTearDown(container.dispose);

    expect(container.read(productPrefixProvider), 'ariya');
  });
}
