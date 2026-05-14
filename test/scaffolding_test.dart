/// Smoke tests for the W3-5 scaffold of kaichen_era_account_storage.
///
/// Validates that:
///   - the package barrel resolves under the declared pubspec.yaml `name:`
///   - `meta` is declared as a production dependency for future primitives
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kaichen_era_account_storage/kaichen_era_account_storage.dart';
import 'package:meta/meta.dart';

void main() {
  group('kaichen_era_account_storage scaffold', () {
    test('package barrel exposes pinned version', () {
      expect(kaichenEraCloudkitSyncVersion, '0.0.1');
    });

    test('production dependency meta resolves', () {
      expect(immutable, isA<Immutable>());
    });
  });
}
