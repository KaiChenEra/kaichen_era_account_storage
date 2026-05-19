# kaichen_era_account_storage

Account-scoped storage primitives shared by the KaiChenEra suite.

This package contains the W3-5 account-scoped SharedPreferences, Keychain install-session sentinel, scoped-key, account-scope, and migration-helper primitives.

Current public API surface:

- `kaichenEraCloudkitSyncVersion`, pinned to the package version.
- `productPrefixProvider`, `currentAccountScopeProvider`, `getActiveScopeForUserId`, `scopedKey`, `anonScope`, `AccountScopedPaths`, and `accountScopedPathsProvider`.
- `ScopedPref`, `ScopedPrefCodec`, and `ScopedSyncedPref`.
- `ensureInstallSessionFresh`.
- `shouldPromptMigration`, `copyScopeStaged`, `markKeepAnon`, `inspectAnonMigrationSummary`, `mergeArrayIndex`, and `migratableKeys`.
- `ICloudPrefController`, `ICloudPrefState`, `ICloudPrefSet`, `EntitlementTier`, `EntitlementTierSource`, `iCloudPrefStateCodec`, and `defaultICloudPrefToggleRawKey`.

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

## iCloud pref sync controller

`ICloudPrefController` owns the on/off state for iCloud preference sync,
with tier-flip-aware auto-toggle (`free → pro` auto-on, `pro → free`
auto-off; sticky once the user has explicitly toggled once) and
per-account-scope rebuild semantics. Each suite app declares its own
`ICloudPrefSet` (product prefix + pref list) and `EntitlementTierSource`
(adapter onto the host's entitlement provider), then subclasses
`ICloudPrefController` with a one-liner:

```dart
class LectioICloudPrefController extends ICloudPrefController {
  LectioICloudPrefController()
      : super(prefSet: LectioPrefSet(), tierSource: LectioTierSource());

  @override
  String get toggleRawKey => PrefKeys.icloudSync;
}

final iCloudPrefProvider =
    NotifierProvider<LectioICloudPrefController, ICloudPrefState>(
  LectioICloudPrefController.new,
);
```

The actual cross-device push (NSUbiquitousKeyValueStore write or CloudKit
upload) is still host-driven for now. `ICloudPrefSet.prefs` holds the pref
list the future KVStore wire will iterate over — populate it today so the
upgrade is a no-op at the call site.
