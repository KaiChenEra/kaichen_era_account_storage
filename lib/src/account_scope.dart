/// Account scope — namespacing for user-specific persisted state.
///
/// Per plan-rosy-music Phase 7b + RN P3.1 §3.
///
/// **Why**: Lectio supports anonymous use (free tier) AND authenticated
/// use (pro tier). When userId flips null → "u-1", the in-memory stores
/// must NOT show the previous user's prefs / credentials / entitlement.
/// We solve this by prefixing every persistent key with the active scope:
///   - anonymous → `lectio.anon.raw_key`
///   - user u-1  → `lectio.user-u-1.raw_key`
///
/// Hosts compute the active scope from their auth/session state and override
/// [currentAccountScopeProvider]. `scopedKey(rawKey)` wraps a raw
/// SharedPreferences key for the current scope.
///
/// **USERID_REGEX**: Defensive — paths like `'../'` could let a
/// malformed userId escape the scope sandbox into another user's
/// namespace. The regex restricts to `[a-zA-Z0-9_-]{1,64}` and we
/// fall back to 'anon' on any mismatch.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Acceptable userId charset. Everything else collapses to 'anon'.
final RegExp _userIdRegex = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

const String _anonScope = 'anon';

/// Computes the scope prefix for a given userId. Pure function — exposed
/// for testing without needing a Riverpod container.
String getActiveScopeForUserId(String? userId) {
  if (userId == null || userId.isEmpty) return _anonScope;
  if (!_userIdRegex.hasMatch(userId)) return _anonScope;
  return 'user-$userId';
}

/// Wraps a raw SharedPreferences key with the active scope prefix.
/// Pure function — caller passes the scope explicitly so tests can use
/// it without spinning up Riverpod.
///
/// e.g. scopedKey(scope: 'user-u-1', rawKey: 'engine_config') →
///      'lectio.user-u-1.engine_config'
String scopedKey({required String scope, required String rawKey}) {
  assert(rawKey.isNotEmpty, 'rawKey must be non-empty');
  return 'lectio.$scope.$rawKey';
}

/// Public constants — exposed for callers that want to compare directly
/// (e.g. UI showing "anonymous mode" badge).
const anonScope = _anonScope;

/// Framework-level source of truth for account-scoped persistence.
///
/// Stores that contain user-specific data must watch this provider instead of
/// manually hydrating on auth changes. Riverpod then rebuilds the store when
/// login/logout switches the active scope.
///
/// This package intentionally has no auth dependency. Host apps should override
/// this provider with their concrete scope source, usually by calling
/// [getActiveScopeForUserId] on the current authenticated user id.
final currentAccountScopeProvider = Provider<String>((ref) => anonScope);

class AccountScopedPaths {
  const AccountScopedPaths(this.scope);

  final String scope;

  Future<Directory> appScopeRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory(p.join(dir.path, 'lectio', 'scopes', scope))
      ..createSync(recursive: true);
  }

  Future<Directory> documentsRoot() async {
    final root = await appScopeRoot();
    return Directory(p.join(root.path, 'documents'))
      ..createSync(recursive: true);
  }
}

final accountScopedPathsProvider = Provider<AccountScopedPaths>((ref) {
  return AccountScopedPaths(ref.watch(currentAccountScopeProvider));
});
