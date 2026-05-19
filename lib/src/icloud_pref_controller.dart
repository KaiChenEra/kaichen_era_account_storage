/// iCloud preference sync controller — tier-flip-aware on/off state for
/// per-account preference sync, with sticky `userSet` semantics.
///
/// This generalises the lectio-specific `ICloudPrefController` (originally in
/// `lectio_app/lib/features/sync/prefs/icloud_pref.dart`) so any suite app can
/// reuse the tier-flip + per-account scope + persistence wiring, declaring
/// only its own pref list via [ICloudPrefSet] and binding its entitlement
/// source via [EntitlementTierSource].
///
/// **Scope (current)**: the controller owns the **on/off state** for iCloud
/// pref sync and the tier-flip semantics. The actual cross-device push (e.g.
/// `NSUbiquitousKeyValueStore` write or CloudKit upload) is host-driven for
/// now: the host's [ScopedPref]s already persist locally; integrating a
/// generic KVStore wire (declared in plan §F1) is reserved for a follow-up PR
/// — see `ICloudPrefSet.prefs` which holds the pref list the future KVStore
/// loop will iterate over.
///
/// **Tier-flip behaviour** (preserved from lectio):
///   - free → pro with `userSet=false` → auto-on (enabled=true)
///   - pro → free with `userSet=false` → auto-off (enabled=false)
///   - after the user explicitly toggles once, `userSet=true` and tier flips
///     no longer touch `enabled`.
///
/// **Per-account scope**: the controller [ref.watch]es
/// [currentAccountScopeProvider]; on login / logout / switch-account the
/// Notifier rebuilds, the in-memory state resets, and the persisted toggle
/// re-hydrates from the new scope's [ScopedPref].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import 'account_scope.dart';
import 'scoped_pref.dart';
import 'scoped_pref_codec.dart';

/// Entitlement tier exposed to the controller. Hosts may model richer tiers
/// internally; what matters to this controller is the free / pro split.
enum EntitlementTier {
  free,
  pro;

  bool get isPro => this == EntitlementTier.pro;
}

/// Host-facing interface for reading the current entitlement tier and
/// listening to tier flips.
///
/// Hosts implement this by adapting their own entitlement provider; the
/// controller treats this as the single source of truth.
abstract class EntitlementTierSource {
  /// Current entitlement tier — read synchronously.
  EntitlementTier readTier(Ref ref);

  /// Registers a tier-change listener on [ref]. The listener fires for every
  /// flip; the controller filters no-op flips internally.
  ///
  /// Implementations typically call `ref.listen` on their underlying tier
  /// provider here.
  void listenTier(
    Ref ref,
    void Function(EntitlementTier? previous, EntitlementTier next) onFlip,
  );
}

/// Host-declared bundle of preferences that should sync through this
/// controller.
///
/// Hosts implement this with the concrete [ScopedPref] / [ScopedSyncedPref]
/// instances they want covered by iCloud sync. The current controller only
/// reads [productPrefix] and uses [prefs] for forward-compatibility (future
/// KVStore wire); the host's own pref instances remain the source of truth
/// for individual reads / writes.
abstract class ICloudPrefSet {
  /// Product prefix this set belongs to (e.g. `'lectio'`, `'ariya'`).
  ///
  /// Must match the product prefix the host injects via
  /// [productPrefixProvider]; the controller asserts this in debug.
  String get productPrefix;

  /// The pref list this controller is responsible for syncing.
  ///
  /// Reserved for the future KVStore wire (plan §F1). Hosts should still
  /// populate this so the upgrade is a no-op at the call site.
  List<ScopedPref<dynamic>> get prefs;
}

/// Persisted state for the iCloud pref sync toggle. Stored per-account-scope
/// via a [ScopedPref] keyed under [ICloudPrefController.toggleRawKey].
@immutable
class ICloudPrefState {
  const ICloudPrefState({
    required this.enabled,
    required this.userSet,
    required this.hydrated,
    this.lastSyncAt,
  });

  /// Whether iCloud pref sync is currently on.
  final bool enabled;

  /// Whether the user has explicitly toggled at least once. Sticky: once true,
  /// tier flips no longer auto-toggle [enabled].
  final bool userSet;

  /// Whether the in-memory state has finished hydrating from persistence.
  /// `false` during the brief window between controller build and first
  /// `ensureHydrated()` completion.
  final bool hydrated;

  /// Timestamp of the most recent successful sync, if any. Reserved for the
  /// future KVStore wire (plan §F1).
  final DateTime? lastSyncAt;

  static const ICloudPrefState initial = ICloudPrefState(
    enabled: false,
    userSet: false,
    hydrated: false,
  );

  ICloudPrefState copyWith({
    bool? enabled,
    bool? userSet,
    bool? hydrated,
    DateTime? lastSyncAt,
  }) {
    return ICloudPrefState(
      enabled: enabled ?? this.enabled,
      userSet: userSet ?? this.userSet,
      hydrated: hydrated ?? this.hydrated,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'userSet': userSet,
        if (lastSyncAt != null)
          'lastSyncAt': lastSyncAt!.toUtc().toIso8601String(),
      };

  factory ICloudPrefState.fromJson(Map<String, dynamic> json) {
    DateTime? parsedSyncAt;
    final raw = json['lastSyncAt'];
    if (raw is String && raw.isNotEmpty) {
      parsedSyncAt = DateTime.tryParse(raw);
    }
    return ICloudPrefState(
      enabled: (json['enabled'] as bool?) ?? false,
      userSet: (json['userSet'] as bool?) ?? false,
      hydrated: true,
      lastSyncAt: parsedSyncAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ICloudPrefState &&
          other.enabled == enabled &&
          other.userSet == userSet &&
          other.hydrated == hydrated &&
          other.lastSyncAt == lastSyncAt);

  @override
  int get hashCode =>
      Object.hash(enabled, userSet, hydrated, lastSyncAt);
}

/// Codec for [ICloudPrefState] used by the underlying [ScopedPref].
final ScopedPrefCodec<ICloudPrefState> iCloudPrefStateCodec =
    ScopedPrefCodec<ICloudPrefState>(
  encode: (value) => jsonEncode(value.toJson()),
  decode: _decodeICloudPrefState,
);

ICloudPrefState _decodeICloudPrefState(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) {
    return ICloudPrefState.fromJson(decoded);
  }
  if (decoded is Map) {
    return ICloudPrefState.fromJson(
      Map<String, dynamic>.from(decoded.cast<dynamic, dynamic>()),
    );
  }
  throw const FormatException('Invalid iCloud preference payload');
}

/// Default raw key used to persist the toggle state. Hosts override it on
/// the controller subclass when they need a different namespace.
const String defaultICloudPrefToggleRawKey = 'icloud_sync';

/// Notifier owning the iCloud pref sync toggle state. Hosts subclass this
/// (one liner) to bind their [ICloudPrefSet] + [EntitlementTierSource] and
/// optionally override [toggleRawKey].
///
/// Example (host):
///
/// ```dart
/// class LectioICloudPrefController extends ICloudPrefController {
///   LectioICloudPrefController()
///       : super(prefSet: LectioPrefSet(), tierSource: LectioTierSource());
///
///   @override
///   String get toggleRawKey => PrefKeys.icloudSync;
/// }
///
/// final iCloudPrefProvider =
///     NotifierProvider<LectioICloudPrefController, ICloudPrefState>(
///   LectioICloudPrefController.new,
/// );
/// ```
abstract class ICloudPrefController extends Notifier<ICloudPrefState> {
  ICloudPrefController({
    required this.prefSet,
    required this.tierSource,
  });

  final ICloudPrefSet prefSet;
  final EntitlementTierSource tierSource;

  /// Raw key under which the toggle state is persisted. Defaults to
  /// `'icloud_sync'`; hosts override to match an existing key namespace.
  String get toggleRawKey => defaultICloudPrefToggleRawKey;

  Future<void>? _hydrating;
  bool _hydrated = false;
  int _buildEpoch = 0;

  @override
  ICloudPrefState build() {
    // Per-account scope: rebuild whenever the active scope flips.
    ref.watch(currentAccountScopeProvider);
    _hydrating = null;
    _hydrated = false;
    _buildEpoch += 1;
    final epoch = _buildEpoch;
    Future.microtask(() {
      if (!ref.mounted || _buildEpoch != epoch) return;
      hydrate();
    });
    // Tier flip: free ↔ pro auto-toggles `enabled` while `userSet` is false.
    tierSource.listenTier(ref, _onTierFlip);
    return ICloudPrefState.initial;
  }

  ScopedPref<ICloudPrefState> get _scopedPref =>
      ref.read(_toggleScopedPrefProvider.notifier);

  late final NotifierProvider<ScopedPref<ICloudPrefState>, ICloudPrefState?>
      _toggleScopedPrefProvider =
      NotifierProvider<ScopedPref<ICloudPrefState>, ICloudPrefState?>(
    () => ScopedPref<ICloudPrefState>(
      rawKey: toggleRawKey,
      codec: iCloudPrefStateCodec,
    ),
  );

  /// Ensures the persisted toggle has been read into [state]. Idempotent and
  /// safe to call concurrently — concurrent calls share one Future.
  Future<void> hydrate() {
    if (_hydrated) return Future<void>.value();
    final epoch = _buildEpoch;
    return _hydrating ??= _hydrate(epoch).whenComplete(() {
      if (_buildEpoch == epoch) _hydrating = null;
    });
  }

  Future<void> _hydrate(int epoch) async {
    final pref = _scopedPref;
    await pref.ensureHydrated();
    if (!ref.mounted || _buildEpoch != epoch) return;
    final loaded = pref.value;
    state = loaded ?? ICloudPrefState.initial.copyWith(hydrated: true);
    _hydrated = true;
  }

  /// User- or system-initiated toggle. When [userInitiated] is true, the
  /// sticky `userSet` flag flips to true so tier flips no longer override.
  Future<void> setEnabled(bool on, {bool userInitiated = true}) async {
    await hydrate();
    if (!ref.mounted) return;
    final next = state.copyWith(
      enabled: on,
      userSet: state.userSet || userInitiated,
    );
    state = next;
    await _scopedPref.set(next);
  }

  /// Records that a successful cross-device sync just happened. Hosts may
  /// call this from their KVStore / CloudKit push pipeline.
  Future<void> markSynced(DateTime at) async {
    await hydrate();
    if (!ref.mounted) return;
    final next = state.copyWith(lastSyncAt: at);
    state = next;
    await _scopedPref.set(next);
  }

  void _onTierFlip(EntitlementTier? prev, EntitlementTier next) {
    if (prev == next) return;
    // Sticky: once the user has spoken, tier flips don't auto-toggle.
    if (state.userSet) return;
    final wasFree = (prev ?? EntitlementTier.free) == EntitlementTier.free;
    final isFree = next == EntitlementTier.free;
    if (wasFree && !isFree) {
      // free → pro: auto-on.
      unawaited(setEnabled(true, userInitiated: false));
    } else if (!wasFree && isFree) {
      // pro → free: auto-off.
      unawaited(setEnabled(false, userInitiated: false));
    }
  }
}
