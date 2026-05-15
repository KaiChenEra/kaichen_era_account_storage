# kaichen_era_account_storage

Account-scoped storage primitives shared by the KaiChenEra suite.

This package contains the W3-5 account-scoped SharedPreferences, Keychain install-session sentinel, scoped-key, account-scope, and migration-helper primitives.

Current public API surface:

- `kaichenEraCloudkitSyncVersion`, pinned to the package version.
- `productPrefixProvider`, `currentAccountScopeProvider`, `getActiveScopeForUserId`, `scopedKey`, `anonScope`, `AccountScopedPaths`, and `accountScopedPathsProvider`.
- `ScopedPref`, `ScopedPrefCodec`, and `ScopedSyncedPref`.
- `ensureInstallSessionFresh`.
- `shouldPromptMigration`, `copyScopeStaged`, `markKeepAnon`, `inspectAnonMigrationSummary`, `mergeArrayIndex`, and `migratableKeys`.

## Suite-wide neutrality

All persisted preference and keychain keys are namespaced by product prefix.
Host apps must override `productPrefixProvider` at boot so suite apps such as
Lectio and Ariya do not collide when sharing this package and App Group:

```dart
ProviderScope(
  overrides: [
    productPrefixProvider.overrideWithValue('lectio'),
  ],
  child: const LectioApp(),
);
```

Pass the same prefix, without a trailing dot, to non-Riverpod entry points:

```dart
await ensureInstallSessionFresh(productPrefix: 'lectio');

final key = scopedKey(
  productPrefix: 'lectio',
  scope: anonScope,
  rawKey: 'engine_config.v2',
);
```
