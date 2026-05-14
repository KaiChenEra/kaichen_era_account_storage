/// Account-scoped storage primitives (SharedPreferences + Keychain facade) shared by KaiChenEra suite.
library;

export 'src/account_scope.dart'
    show
        AccountScopedPaths,
        accountScopedPathsProvider,
        anonScope,
        currentAccountScopeProvider,
        getActiveScopeForUserId,
        scopedKey;
export 'src/install_session.dart' show ensureInstallSessionFresh;
export 'src/scoped_pref.dart' show ScopedPref;
export 'src/scoped_pref_codec.dart' show ScopedPrefCodec;
export 'src/scoped_synced_pref.dart'
    show ScopedSyncedPref, ScopedSyncedPrefEnqueuePush;
export 'src/scope_migration.dart'
    show
        AnonMigrationSummary,
        copyScopeStaged,
        inspectAnonMigrationSummary,
        markKeepAnon,
        mergeArrayIndex,
        migratableKeys,
        shouldPromptMigration;

/// Pinned version. Keep in sync with pubspec.yaml.
const String kaichenEraCloudkitSyncVersion = '0.0.2';
