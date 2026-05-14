# kaichen_era_account_storage

Account-scoped storage primitives shared by the KaiChenEra suite.

This package contains the W3-5 account-scoped SharedPreferences, Keychain install-session sentinel, scoped-key, account-scope, and migration-helper primitives.

Current public API surface:

- `kaichenEraCloudkitSyncVersion`, pinned to the package version.
- `currentAccountScopeProvider`, `getActiveScopeForUserId`, `scopedKey`, `anonScope`, `AccountScopedPaths`, and `accountScopedPathsProvider`.
- `ScopedPref`, `ScopedPrefCodec`, and `ScopedSyncedPref`.
- `ensureInstallSessionFresh`.
- `shouldPromptMigration`, `copyScopeStaged`, `markKeepAnon`, `inspectAnonMigrationSummary`, `mergeArrayIndex`, and `migratableKeys`.
