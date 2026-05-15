/// scope_migration — anonymous → user-X first-time data migration.
///
/// Per plan-rosy-music Phase 7b + RN A.6.10.
///
/// **When this fires**: userId flips null → "u-1" for the FIRST time AND
/// the anon scope has user-visible data worth asking about.
///
/// **Two options**:
///   1. 「并入账号(推荐)」 — copyScopeStaged(): copy MIGRATABLE_KEYS from
///      anon to user-X scope; clear anon. User keeps their prefs.
///   2. 「保留在本机不上传」 — markKeepAnon(): anon scope stays as-is,
///      record the choice so the prompt doesn't re-fire. User explicitly
///      wants the new account fresh.
///
/// **MIGRATABLE_KEYS**: prefs that are sensible to carry over. Excludes
/// session-specific state (auth tokens, userId) and ephemeral OCR job
/// state (in-flight jobs are tied to the current device, not the
/// account).
///
/// **mergeArrayIndex**: pure helper used during copy when both scopes
/// have a list-shaped index (e.g. credentials.index). Dedups by `id`,
/// preserves order of existing user-scope entries first then appends
/// anon-only entries. Pure function → unit-testable without
/// SharedPreferences.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'account_scope.dart';

/// Keys that survive an anon → user migration. Format is the RAW key
/// (without scope prefix); migration applies the prefix on each side.
///
/// Add to this list when introducing a new scope-aware preference that
/// users would want carried over from their anonymous trial.
const Set<String> migratableKeys = {
  'engine_config.v2',
  'icloud_sync.v1',
  'concurrent_limit_override.v1',
  'home_mode.v1',
  'strategy.v1',
  'post_capture_action.v1',
  'credential_intro_seen',
  'credentials.index',
  'pages_processed.v1',
  'usage.log',
  'docs.index',
  'cloudkit.push_queue.v1',
};

String _migrationDecisionKey(String productPrefix) =>
    '$productPrefix._migration.decision.v1';

class AnonMigrationSummary {
  const AnonMigrationSummary({
    required this.documentCount,
    required this.credentialCount,
    required this.preferenceLabels,
    required this.documentFileCount,
  });

  final int documentCount;
  final int credentialCount;
  final List<String> preferenceLabels;
  final int documentFileCount;

  bool get hasData =>
      documentCount > 0 ||
      credentialCount > 0 ||
      preferenceLabels.isNotEmpty ||
      documentFileCount > 0;

  List<String> get dialogLines {
    final lines = <String>[];
    if (credentialCount > 0) {
      lines.add('Key: $credentialCount 个');
    }
    if (documentCount > 0) {
      lines.add('文稿: $documentCount 个');
    }
    if (preferenceLabels.isNotEmpty) {
      lines.add('偏好: ${preferenceLabels.join('、')}');
    }
    if (documentFileCount > 0) {
      lines.add('文稿源文件: $documentFileCount 个文件');
    }
    return lines;
  }

  String get dialogText => dialogLines.join('\n');
}

/// Returns true if we should prompt the user for migration on this
/// sign-in. Pure — caller passes SharedPreferences.
Future<bool> shouldPromptMigration({
  required String productPrefix,
  required String fromScope,
  required String toScope,
  required SharedPreferences prefs,
}) async {
  assert(productPrefix.isNotEmpty, 'productPrefix must be non-empty');
  // Only prompt on anon → user transitions
  if (fromScope != anonScope) return false;
  if (toScope == anonScope) return false;

  // 1. Has user already made a permanent decision (merge / keep)?
  final decision = prefs.getString(
    '${_migrationDecisionKey(productPrefix)}.$toScope',
  );
  if (decision != null) return false;

  // 2. Does the anon scope have user-visible data worth asking about?
  return (await inspectAnonMigrationSummary(
    productPrefix: productPrefix,
    prefs: prefs,
  ))
      .hasData;
}

Future<AnonMigrationSummary> inspectAnonMigrationSummary({
  required String productPrefix,
  required SharedPreferences prefs,
}) async {
  assert(productPrefix.isNotEmpty, 'productPrefix must be non-empty');
  final files = await _countAnonScopedFiles();
  return AnonMigrationSummary(
    documentCount: _jsonArrayLength(
      prefs.getString(
        scopedKey(
          productPrefix: productPrefix,
          scope: anonScope,
          rawKey: 'docs.index',
        ),
      ),
    ),
    credentialCount: _jsonArrayLength(
      prefs.getString(
        scopedKey(
          productPrefix: productPrefix,
          scope: anonScope,
          rawKey: 'credentials.index',
        ),
      ),
    ),
    preferenceLabels: _meaningfulPreferenceLabels(productPrefix, prefs),
    documentFileCount: files.documents,
  );
}

List<String> _meaningfulPreferenceLabels(
  String productPrefix,
  SharedPreferences prefs,
) {
  final labels = <String>[];
  final engineRaw = prefs.getString(
    scopedKey(
      productPrefix: productPrefix,
      scope: anonScope,
      rawKey: 'engine_config.v2',
    ),
  );
  if (engineRaw != null && !_isDefaultEngineConfig(engineRaw)) {
    labels.add('识别引擎');
  }

  final iCloudRaw = prefs.getString(
    scopedKey(
      productPrefix: productPrefix,
      scope: anonScope,
      rawKey: 'icloud_sync.v1',
    ),
  );
  if (iCloudRaw != null && _isMeaningfulICloudPref(iCloudRaw)) {
    labels.add('iCloud');
  }

  final concurrent = prefs.getInt(
    scopedKey(
      productPrefix: productPrefix,
      scope: anonScope,
      rawKey: 'concurrent_limit_override.v1',
    ),
  );
  if (concurrent != null && concurrent > 1) {
    labels.add('并发数');
  }

  final homeMode = prefs.getString(
    scopedKey(
      productPrefix: productPrefix,
      scope: anonScope,
      rawKey: 'home_mode.v1',
    ),
  );
  if (homeMode != null && homeMode != 'camera') {
    labels.add('首页入口');
  }

  final roundRobin = prefs.getBool(
    scopedKey(
      productPrefix: productPrefix,
      scope: anonScope,
      rawKey: 'strategy.v1',
    ),
  );
  if (roundRobin == true) {
    labels.add('Key 轮询');
  }

  final postCapture = prefs.getString(
    scopedKey(
      productPrefix: productPrefix,
      scope: anonScope,
      rawKey: 'post_capture_action.v1',
    ),
  );
  if (postCapture == 'detail' || postCapture == 'document') {
    labels.add('识别后跳转');
  }

  return labels;
}

bool _isDefaultEngineConfig(String raw) {
  final decoded = _tryJsonDecode(raw);
  if (decoded is! Map) return false;
  final active = decoded['activeEngineId'];
  final byEngine = decoded['byEngineId'];
  if (active != 'apple_vision' || byEngine is! Map || byEngine.length != 1) {
    return false;
  }
  final apple = byEngine['apple_vision'];
  if (apple is! Map) return false;
  final extras = apple['extras'];
  final locale = apple['locale'];
  return apple['engineId'] == 'apple_vision' &&
      (locale == null || locale == 'auto') &&
      (extras is! Map || extras.isEmpty);
}

bool _isMeaningfulICloudPref(String raw) {
  final decoded = _tryJsonDecode(raw);
  if (decoded is! Map) return true;
  return decoded['enabled'] == true || decoded['userSet'] == true;
}

int _jsonArrayLength(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 0;
  final decoded = _tryJsonDecode(raw);
  if (decoded is List) return decoded.length;
  return 1;
}

Object? _tryJsonDecode(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

Future<({int documents})> _countAnonScopedFiles() async {
  final roots = await _scopedFileRoots(anonScope);
  return (documents: await _countFiles(roots[0]));
}

Future<int> _countFiles(Directory dir) async {
  if (!await dir.exists()) return 0;
  var count = 0;
  await for (final entry in dir.list(recursive: true, followLinks: false)) {
    if (entry is File && await entry.length() > 0) count++;
  }
  return count;
}

// ─── User decisions ─────────────────────────────────────────────────

/// User picked 「并入账号」. Copies the anon → user scope for every
/// MIGRATABLE_KEY, removes anon scope's copies, and records the choice.
///
/// Pure-ish: side-effects through SharedPreferences only. Returns the
/// list of keys actually copied (some may be absent in anon).
Future<List<String>> copyScopeStaged({
  required String productPrefix,
  required String userScope,
  required SharedPreferences prefs,
}) async {
  assert(productPrefix.isNotEmpty, 'productPrefix must be non-empty');
  final copied = <String>[];
  final previousUserValues = <String, Object?>{};
  final anonKeysToRemove = <String>[];
  for (final raw in migratableKeys) {
    final fromKey = scopedKey(
      productPrefix: productPrefix,
      scope: anonScope,
      rawKey: raw,
    );
    final toKey = scopedKey(
      productPrefix: productPrefix,
      scope: userScope,
      rawKey: raw,
    );
    final value = prefs.get(fromKey);
    if (value == null) continue;
    previousUserValues[toKey] = prefs.get(toKey);

    // For list-shaped indices, merge with any existing user-scope entry
    // (e.g. user signed in on another device — their credentials.index
    // already has rows; we need to add anon ones, not replace).
    if ((raw == 'credentials.index' || raw == 'docs.index') &&
        value is String) {
      final existing = prefs.getString(toKey);
      final merged = mergeArrayIndex(srcRaw: value, existingRaw: existing);
      await prefs.setString(toKey, merged);
    } else if (value is String) {
      await prefs.setString(toKey, value);
    } else if (value is bool) {
      await prefs.setBool(toKey, value);
    } else if (value is int) {
      await prefs.setInt(toKey, value);
    } else if (value is double) {
      await prefs.setDouble(toKey, value);
    } else if (value is List<String>) {
      await prefs.setStringList(toKey, value);
    }
    anonKeysToRemove.add(fromKey);
    copied.add(raw);
  }
  try {
    await migrateAnonScopedFilesToUser(userScope: userScope);
  } catch (_) {
    for (final entry in previousUserValues.entries) {
      await _restorePrefValue(prefs, entry.key, entry.value);
    }
    rethrow;
  }
  for (final key in anonKeysToRemove) {
    await prefs.remove(key);
  }
  await prefs.setString(
    '${_migrationDecisionKey(productPrefix)}.$userScope',
    'merged',
  );
  return copied;
}

/// User picked 「保留在本机不上传」. Anon scope stays intact; record the
/// choice so the prompt doesn't re-fire on this user.
Future<void> markKeepAnon({
  required String productPrefix,
  required String userScope,
  required SharedPreferences prefs,
}) async {
  assert(productPrefix.isNotEmpty, 'productPrefix must be non-empty');
  await prefs.setString(
    '${_migrationDecisionKey(productPrefix)}.$userScope',
    'keep_anon',
  );
}

// ─── Pure helpers ────────────────────────────────────────────────────

/// Merge two JSON-encoded array indices, deduplicating by `id`. Preserves
/// existing order first, then appends anon-only entries.
///
/// Inputs are JSON strings (each `[{id: "...", ...}, ...]`); output is a
/// JSON string of the merged array. Pure — testable without prefs.
///
/// On parse failure, returns the existing string unchanged (anon won't
/// merge in if existing is malformed). On both null/empty, returns '[]'.
String mergeArrayIndex({required String srcRaw, String? existingRaw}) {
  if (existingRaw == null || existingRaw.isEmpty) return srcRaw;
  if (srcRaw.isEmpty) return existingRaw;

  List<dynamic> existing;
  List<dynamic> src;
  try {
    existing = jsonDecode(existingRaw) as List<dynamic>;
    src = jsonDecode(srcRaw) as List<dynamic>;
  } catch (_) {
    return existingRaw;
  }

  final seen = <String>{};
  final merged = <dynamic>[];
  for (final entry in existing) {
    if (entry is Map && entry['id'] is String) {
      seen.add(entry['id'] as String);
    }
    merged.add(entry);
  }
  for (final entry in src) {
    if (entry is Map && entry['id'] is String) {
      final id = entry['id'] as String;
      if (seen.contains(id)) continue;
      seen.add(id);
    }
    merged.add(entry);
  }
  return jsonEncode(merged);
}

Future<void> migrateAnonScopedFilesToUser({required String userScope}) async {
  final fromRoots = await _scopedFileRoots(anonScope);
  final toRoots = await _scopedFileRoots(userScope);
  final copied = <FileSystemEntity>[];
  final anonToRemove = <FileSystemEntity>[];
  try {
    for (var i = 0; i < fromRoots.length; i++) {
      await _copyDirectoryContents(
        from: fromRoots[i],
        to: toRoots[i],
        copied: copied,
        anonToRemove: anonToRemove,
      );
    }
  } catch (_) {
    for (final entity in copied.reversed) {
      try {
        if (entity is Directory && await entity.exists()) {
          await entity.delete(recursive: true);
        } else if (entity is File && await entity.exists()) {
          await entity.delete();
        }
      } catch (_) {}
    }
    rethrow;
  }
  for (final entity in anonToRemove.reversed) {
    try {
      if (entity is Directory && await entity.exists()) {
        await entity.delete(recursive: true);
      } else if (entity is File && await entity.exists()) {
        await entity.delete();
      }
    } catch (_) {}
  }
}

Future<List<Directory>> _scopedFileRoots(String scope) async {
  final paths = AccountScopedPaths(scope);
  return [await paths.documentsRoot()];
}

Future<void> _copyDirectoryContents({
  required Directory from,
  required Directory to,
  required List<FileSystemEntity> copied,
  required List<FileSystemEntity> anonToRemove,
}) async {
  if (!await from.exists()) return;
  to.createSync(recursive: true);
  await for (final entity in from.list(followLinks: false)) {
    final dest = p.join(to.path, p.basename(entity.path));
    if (entity is Directory) {
      final destDir = Directory(dest);
      if (!await destDir.exists()) {
        await _copyDirectory(entity, destDir);
        copied.add(destDir);
      }
      anonToRemove.add(entity);
    } else if (entity is File) {
      final destFile = File(dest);
      if (!await destFile.exists()) {
        destFile.parent.createSync(recursive: true);
        await entity.copy(destFile.path);
        copied.add(destFile);
      }
      anonToRemove.add(entity);
    }
  }
}

Future<void> _copyDirectory(Directory from, Directory to) async {
  to.createSync(recursive: true);
  await for (final entity in from.list(followLinks: false)) {
    final dest = p.join(to.path, p.basename(entity.path));
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(dest));
    } else if (entity is File) {
      final destFile = File(dest);
      destFile.parent.createSync(recursive: true);
      await entity.copy(destFile.path);
    }
  }
}

Future<void> _restorePrefValue(
  SharedPreferences prefs,
  String key,
  Object? value,
) async {
  if (value == null) {
    await prefs.remove(key);
  } else if (value is String) {
    await prefs.setString(key, value);
  } else if (value is bool) {
    await prefs.setBool(key, value);
  } else if (value is int) {
    await prefs.setInt(key, value);
  } else if (value is double) {
    await prefs.setDouble(key, value);
  } else if (value is List<String>) {
    await prefs.setStringList(key, value);
  }
}
