/// install_session — control-flow tests.
///
/// Native keychain behavior (deleteAll scope, sibling-app isolation,
/// iCloud Keychain non-sync) is NOT covered here — those need the
/// integration test in `integration_test/install_session_test.dart`.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaichen_era_account_storage/kaichen_era_account_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStorage implements FlutterSecureStorage {
  _FakeSecureStorage(Map<String, String> seed) : _data = Map.of(seed);
  final Map<String, String> _data;
  int deleteCalls = 0;

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async =>
      Map.of(_data);

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async {
    deleteCalls++;
    _data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ensureInstallSessionFresh', () {
    test('fresh install: wipes lectio.* keys and writes sentinel', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = _FakeSecureStorage({
        'lectio.jwt.access': 'tok',
        'lectio.device.id': 'dev-1',
        'lectio.creds.abc': '{}',
        'ariya.session': 'KEEP-ME',
      });

      final isFirst = await ensureInstallSessionFresh(
        productPrefix: 'lectio',
        storageOverride: storage,
      );

      expect(isFirst, isTrue);
      expect(storage._data.keys, ['ariya.session']);
      expect(storage._data['ariya.session'], 'KEEP-ME');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('lectio.app.install.initialized.v1'), isTrue);
    });

    test('sentinel present: does nothing, returns false', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'lectio.app.install.initialized.v1': true,
      });
      final storage = _FakeSecureStorage({'lectio.jwt.access': 'tok'});

      final isFirst = await ensureInstallSessionFresh(
        productPrefix: 'lectio',
        storageOverride: storage,
      );

      expect(isFirst, isFalse);
      expect(storage.deleteCalls, 0);
      expect(storage._data['lectio.jwt.access'], 'tok');
    });

    test('idempotent: second call in same session is a no-op', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = _FakeSecureStorage({'lectio.jwt.access': 'tok'});

      final first = await ensureInstallSessionFresh(
        productPrefix: 'lectio',
        storageOverride: storage,
      );
      final second = await ensureInstallSessionFresh(
        productPrefix: 'lectio',
        storageOverride: storage,
      );

      expect(first, isTrue);
      expect(second, isFalse);
      expect(storage.deleteCalls, 1);
    });

    test('empty keychain: still writes sentinel without error', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = _FakeSecureStorage({});

      final isFirst = await ensureInstallSessionFresh(
        productPrefix: 'lectio',
        storageOverride: storage,
      );

      expect(isFirst, isTrue);
      expect(storage.deleteCalls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('lectio.app.install.initialized.v1'), isTrue);
    });

    test('fresh install: ariya prefix only wipes ariya keys', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = _FakeSecureStorage({
        'ariya.jwt.access': 'tok',
        'ariya.device.id': 'dev-1',
        'lectio.jwt.access': 'KEEP-ME',
      });

      final isFirst = await ensureInstallSessionFresh(
        productPrefix: 'ariya',
        storageOverride: storage,
      );

      expect(isFirst, isTrue);
      expect(storage._data.keys, ['lectio.jwt.access']);
      expect(storage._data['lectio.jwt.access'], 'KEEP-ME');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ariya.app.install.initialized.v1'), isTrue);
      expect(prefs.getBool('lectio.app.install.initialized.v1'), isNull);
    });
  });
}
