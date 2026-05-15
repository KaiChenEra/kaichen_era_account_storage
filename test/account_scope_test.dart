/// Account scope: scopedKey + USERID_REGEX defense.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kaichen_era_account_storage/kaichen_era_account_storage.dart';

void main() {
  group('getActiveScopeForUserId', () {
    test('null userId → anon', () {
      expect(getActiveScopeForUserId(null), 'anon');
    });

    test('empty userId → anon', () {
      expect(getActiveScopeForUserId(''), 'anon');
    });

    test('valid userId → user-<id>', () {
      expect(getActiveScopeForUserId('u-1'), 'user-u-1');
      expect(getActiveScopeForUserId('alice_123'), 'user-alice_123');
    });

    test('USERID_REGEX rejects path-traversal', () {
      expect(getActiveScopeForUserId('../malicious'), 'anon');
      expect(getActiveScopeForUserId('a/b'), 'anon');
      expect(getActiveScopeForUserId('a.b'), 'anon');
      expect(getActiveScopeForUserId('a b'), 'anon');
    });

    test('rejects strings longer than 64 chars', () {
      final long = 'x' * 65;
      expect(getActiveScopeForUserId(long), 'anon');
    });

    test('accepts exactly 64 chars', () {
      final ok = 'x' * 64;
      expect(getActiveScopeForUserId(ok), 'user-$ok');
    });
  });

  group('scopedKey', () {
    test('scopedKey wraps with product prefix', () {
      expect(
        scopedKey(productPrefix: 'test', scope: 'foo', rawKey: 'bar'),
        'test.foo.bar',
      );
      expect(
        scopedKey(productPrefix: 'ariya', scope: 'user-u-1', rawKey: 'theme'),
        'ariya.user-u-1.theme',
      );
    });
  });
}
