/// Phase 7b — scope_migration: shouldPromptMigration + copyScopeStaged +
/// markKeepAnon + mergeArrayIndex pure helper.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaichen_era_account_storage/kaichen_era_account_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _productPrefix = 'ariya';

String _scopedKey({required String scope, required String rawKey}) {
  return scopedKey(productPrefix: _productPrefix, scope: scope, rawKey: rawKey);
}

void main() {
  late Directory root;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = await Directory.systemTemp.createTemp('ariya_scope_migration_test_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  group('shouldPromptMigration', () {
    test('false when fromScope is not anon', () async {
      final prefs = await SharedPreferences.getInstance();
      // Plant some anon data so we'd otherwise prompt
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'home_mode.v1'),
        'dark',
      );

      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: 'user-old',
          toScope: 'user-new',
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('false when toScope is anon (signing out)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'home_mode.v1'),
        'dark',
      );

      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: anonScope,
          toScope: anonScope,
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('false when anon scope is empty', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: anonScope,
          toScope: 'user-1',
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('true when anon has migratable data and no prior decision', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'engine_config.v2'),
        jsonEncode({
          'activeEngineId': 'azure_doc_intel',
          'byEngineId': {
            'apple_vision': {
              'engineId': 'apple_vision',
              'locale': 'auto',
              'extras': {},
            },
            'azure_doc_intel': {
              'engineId': 'azure_doc_intel',
              'locale': 'auto',
              'extras': {},
            },
          },
        }),
      );

      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: anonScope,
          toScope: 'user-1',
          prefs: prefs,
        ),
        isTrue,
      );
    });

    test('false when anon only has default preference writes', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'engine_config.v2'),
        jsonEncode({
          'activeEngineId': 'apple_vision',
          'byEngineId': {
            'apple_vision': {
              'engineId': 'apple_vision',
              'locale': 'auto',
              'extras': {},
            },
          },
        }),
      );
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'home_mode.v1'),
        'camera',
      );
      await prefs.setBool(
        _scopedKey(scope: anonScope, rawKey: 'strategy.v1'),
        false,
      );
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'post_capture_action.v1'),
        'home',
      );
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'icloud_sync.v1'),
        '{"enabled":false,"userSet":false}',
      );
      await prefs.setInt(
        _scopedKey(scope: anonScope, rawKey: 'concurrent_limit_override.v1'),
        1,
      );

      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: anonScope,
          toScope: 'user-1',
          prefs: prefs,
        ),
        isFalse,
      );
      expect(
        (await inspectAnonMigrationSummary(
          productPrefix: _productPrefix,
          prefs: prefs,
        ))
            .dialogLines,
        isEmpty,
      );
    });

    test('false when anon only has internal stats or queues', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _scopedKey(scope: anonScope, rawKey: 'pages_processed.v1'),
        3,
      );
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'usage.log'),
        '[{"ts":1}]',
      );
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'cloudkit.push_queue.v1'),
        '[{"id":"q1"}]',
      );

      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: anonScope,
          toScope: 'user-1',
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('false when user-visible indices are empty', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'docs.index'),
        '[]',
      );
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'credentials.index'),
        '[]',
      );

      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: anonScope,
          toScope: 'user-1',
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('true when anon has scoped files', () async {
      final prefs = await SharedPreferences.getInstance();
      final docsRoot = await const AccountScopedPaths(
        anonScope,
      ).documentsRoot();
      await docsRoot.create(recursive: true);
      await File('${docsRoot.path}/doc-1.json').writeAsString('{"id":"doc-1"}');

      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: anonScope,
          toScope: 'user-1',
          prefs: prefs,
        ),
        isTrue,
      );
    });

    test('summary lists the data that will be migrated', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'docs.index'),
        jsonEncode([
          {'id': 'doc-1'},
          {'id': 'doc-2'},
        ]),
      );
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'credentials.index'),
        jsonEncode([
          {'id': 'cred-1'},
        ]),
      );
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'home_mode.v1'),
        'gallery',
      );
      final docsRoot = await const AccountScopedPaths(
        anonScope,
      ).documentsRoot();
      await docsRoot.create(recursive: true);
      await File(
        '${docsRoot.path}/doc-1/manifest.json',
      ).create(recursive: true);
      await File('${docsRoot.path}/doc-1/manifest.json').writeAsString('{}');

      final summary = await inspectAnonMigrationSummary(
        productPrefix: _productPrefix,
        prefs: prefs,
      );

      expect(summary.hasData, isTrue);
      expect(
        summary.dialogLines,
        containsAll(['Key: 1 个', '文稿: 2 个', '偏好: 首页入口', '文稿源文件: 1 个文件']),
      );
    });

    test('false when user already chose merged', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'home_mode.v1'),
        'dark',
      );
      await markKeepAnon(
        productPrefix: _productPrefix,
        userScope: 'user-1',
        prefs: prefs,
      );

      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: anonScope,
          toScope: 'user-1',
          prefs: prefs,
        ),
        isFalse,
      );
    });
  });

  group('copyScopeStaged', () {
    test('copies migratable keys from anon → user, removes anon', () async {
      final prefs = await SharedPreferences.getInstance();
      // Plant 3 different types
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'engine_config.v2'),
        '{"engineId":"apple_vision"}',
      );
      await prefs.setBool(
        _scopedKey(scope: anonScope, rawKey: 'icloud_sync.v1'),
        true,
      );
      await prefs.setInt(
        _scopedKey(scope: anonScope, rawKey: 'concurrent_limit_override.v1'),
        3,
      );

      final copied = await copyScopeStaged(
        productPrefix: _productPrefix,
        userScope: 'user-1',
        prefs: prefs,
      );

      expect(
        copied,
        containsAll([
          'engine_config.v2',
          'icloud_sync.v1',
          'concurrent_limit_override.v1',
        ]),
      );
      expect(
        prefs.getString(
          _scopedKey(scope: 'user-1', rawKey: 'engine_config.v2'),
        ),
        '{"engineId":"apple_vision"}',
      );
      expect(
        prefs.getBool(_scopedKey(scope: 'user-1', rawKey: 'icloud_sync.v1')),
        isTrue,
      );
      expect(
        prefs.getInt(
          _scopedKey(scope: 'user-1', rawKey: 'concurrent_limit_override.v1'),
        ),
        3,
      );
      // Anon copies removed
      expect(
        prefs.containsKey(
          _scopedKey(scope: anonScope, rawKey: 'engine_config.v2'),
        ),
        isFalse,
      );
    });

    test('credentials.index merges with existing user-scope', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'credentials.index'),
        jsonEncode([
          {'id': 'a-1', 'label': 'Anon Azure'},
          {'id': 'shared', 'label': 'Anon copy of shared'},
        ]),
      );
      await prefs.setString(
        _scopedKey(scope: 'user-1', rawKey: 'credentials.index'),
        jsonEncode([
          {'id': 'u-1', 'label': 'User Azure'},
          {'id': 'shared', 'label': 'User copy of shared'},
        ]),
      );

      await copyScopeStaged(
        productPrefix: _productPrefix,
        userScope: 'user-1',
        prefs: prefs,
      );

      final merged = jsonDecode(
        prefs.getString(
          _scopedKey(scope: 'user-1', rawKey: 'credentials.index'),
        )!,
      );
      // Existing user entries first, then anon-only entries (shared dedupped to user's copy)
      expect(merged, hasLength(3));
      expect(merged[0]['id'], 'u-1');
      expect(merged[1]['id'], 'shared');
      expect(merged[1]['label'], 'User copy of shared'); // user wins on dedup
      expect(merged[2]['id'], 'a-1');
    });

    test('records merged decision', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'home_mode.v1'),
        'dark',
      );

      await copyScopeStaged(
        productPrefix: _productPrefix,
        userScope: 'user-1',
        prefs: prefs,
      );

      // shouldPromptMigration → false now (decision recorded)
      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: anonScope,
          toScope: 'user-1',
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('handles missing keys gracefully', () async {
      final prefs = await SharedPreferences.getInstance();
      // No anon data
      final copied = await copyScopeStaged(
        productPrefix: _productPrefix,
        userScope: 'user-1',
        prefs: prefs,
      );
      expect(copied, isEmpty);
    });
  });

  group('mergeArrayIndex (pure)', () {
    test('returns srcRaw when existing is null/empty', () {
      expect(mergeArrayIndex(srcRaw: '[1,2]', existingRaw: null), '[1,2]');
      expect(mergeArrayIndex(srcRaw: '[1,2]', existingRaw: ''), '[1,2]');
    });

    test('returns existingRaw when src is empty', () {
      expect(mergeArrayIndex(srcRaw: '', existingRaw: '[1,2]'), '[1,2]');
    });

    test('dedups by id, existing wins', () {
      final src = jsonEncode([
        {'id': 'a', 'label': 'src-A'},
        {'id': 'b', 'label': 'src-B'},
      ]);
      final existing = jsonEncode([
        {'id': 'a', 'label': 'existing-A'},
      ]);
      final merged = jsonDecode(
        mergeArrayIndex(srcRaw: src, existingRaw: existing),
      );
      expect(merged, hasLength(2));
      expect(merged[0]['label'], 'existing-A');
      expect(merged[1]['id'], 'b');
    });

    test('preserves order: existing first, then src-only', () {
      final src = jsonEncode([
        {'id': 'x'},
        {'id': 'y'},
      ]);
      final existing = jsonEncode([
        {'id': 'a'},
        {'id': 'b'},
      ]);
      final merged = jsonDecode(
        mergeArrayIndex(srcRaw: src, existingRaw: existing),
      );
      expect(merged.map((e) => e['id']).toList(), ['a', 'b', 'x', 'y']);
    });

    test('returns existing on parse failure (defensive)', () {
      const malformed = '{not json';
      expect(mergeArrayIndex(srcRaw: '[1]', existingRaw: malformed), malformed);
    });

    test('appends entries without id field', () {
      final src = jsonEncode([
        {'no-id-field': true},
      ]);
      final existing = jsonEncode([
        {'id': 'a'},
      ]);
      final merged = jsonDecode(
        mergeArrayIndex(srcRaw: src, existingRaw: existing),
      );
      expect(merged, hasLength(2));
    });
  });

  group('markKeepAnon', () {
    test('markKeepAnon blocks future prompts', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopedKey(scope: anonScope, rawKey: 'home_mode.v1'),
        'dark',
      );

      await markKeepAnon(
        productPrefix: _productPrefix,
        userScope: 'user-1',
        prefs: prefs,
      );

      expect(
        await shouldPromptMigration(
          productPrefix: _productPrefix,
          fromScope: anonScope,
          toScope: 'user-1',
          prefs: prefs,
        ),
        isFalse,
      );
    });
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
