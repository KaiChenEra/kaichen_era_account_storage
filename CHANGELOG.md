# Changelog

All notable changes to `kaichen_era_account_storage` are documented here.

## 0.0.4

- Added `ICloudPrefController` — generic Notifier owning the iCloud pref
  sync toggle state with tier-flip auto-toggle (`free → pro` auto-on,
  `pro → free` auto-off, sticky once user has toggled once) and per-account
  scope rebuild semantics.
- Added supporting types: `ICloudPrefState`, `ICloudPrefSet`,
  `EntitlementTier`, `EntitlementTierSource`, `iCloudPrefStateCodec`,
  `defaultICloudPrefToggleRawKey`.
- This replaces lectio's host-local `ICloudPrefController` (~100 LOC). A
  follow-up PR will refactor lectio to subclass the kit controller and
  declare a `LectioPrefSet`; ariya gains the same wire by declaring its
  own `AriyaPrefSet`. Cross-device push (NSUbiquitousKeyValueStore /
  CloudKit) is still host-driven; the kit holds the pref list
  (`ICloudPrefSet.prefs`) reserved for the future KVStore wire.

## 0.0.3

- Parameterize product prefix (was hardcoded 'lectio.'). All callers must
  now pass `productPrefix` explicitly or override `productPrefixProvider`.
  Breaks: scopedKey() and ensureInstallSessionFresh() signatures.

## 0.0.2 — 2026-05-15 — Storage primitives (W3-5-impl)

- Lifted account-scoped storage primitives from `lectio_app`.
- Added scoped SharedPreferences, synced preference callback facade, install-session sentinel, scoped paths, and anon-to-user migration helpers.
- Exported the package public API for the W3-5 host switch follow-up.

## 0.0.1 — 2026-05-15 — Scaffold (W3-5)

- Initial Flutter package scaffold.
- Empty public barrel reserved for W3-5-impl storage primitives.
- Sanity tests cover package resolution and dependency wiring.
