# Changelog

All notable changes to `kaichen_era_account_storage` are documented here.

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
