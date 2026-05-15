/// install_session — detect first launch after (re)install and wipe local
/// keychain state that survives iOS / macOS uninstall.
///
/// Why: iOS + macOS Keychain entries with `kSecAttrAccessibleAfterFirstUnlock`
/// persist across app uninstall. SharedPreferences IS wiped on uninstall,
/// so the absence of the product-specific sentinel is a reliable "fresh
/// install" signal.
///
/// Platform coverage:
///   - iOS: covered. App Group + keychain-access-groups configured in
///     `ios/Runner/Lectio.entitlements`.
///   - macOS: covered. Matching entitlements added in both
///     `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`
///     (sandbox + App Group + keychain-access-groups).
///   - Android: Keystore is wiped by the OS on uninstall, so [readAll] +
///     filter is effectively a no-op (only entries already present in
///     this session are seen). Wipe call is safe but redundant.
///
/// Invariants (do not relax without updating wipe semantics):
///   - All product keychain entries are written with
///     `KeychainAccessibility.first_unlock_this_device`, which implies
///     `kSecAttrSynchronizable = false` → no iCloud Keychain re-sync.
///   - All product keys are prefixed `<product>.` — we DELETE BY PREFIX,
///     not `deleteAll()`, to avoid wiping sibling apps (ariya etc.) that
///     share App Group `group.com.kaiChenEra.suite`.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _sentinelKey(String productPrefix) =>
    '$productPrefix.app.install.initialized.v1';

const _kSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    groupId: 'group.com.kaiChenEra.suite',
  ),
  mOptions: MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    groupId: 'group.com.kaiChenEra.suite',
  ),
  // ignore: deprecated_member_use
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Returns true iff this was the first launch after install.
/// Idempotent — safe to call multiple times in one session.
Future<bool> ensureInstallSessionFresh({
  required String productPrefix,
  FlutterSecureStorage? storageOverride,
}) async {
  assert(productPrefix.isNotEmpty, 'productPrefix must be non-empty');
  final sentinel = _sentinelKey(productPrefix);
  final wipePrefix = '$productPrefix.';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(sentinel) == true) return false;

  final storage = storageOverride ?? _kSecureStorage;

  // readAll() returns every entry visible to this app's service+accessGroup;
  // we filter to productPrefix.* so sibling apps in the same App Group are safe.
  final all = await storage.readAll();
  for (final key in all.keys) {
    if (key.startsWith(wipePrefix)) {
      await storage.delete(key: key);
    }
  }

  await prefs.setBool(sentinel, true);
  return true;
}
