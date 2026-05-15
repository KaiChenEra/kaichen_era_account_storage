/// Generic account-scoped SharedPreferences facade.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_scope.dart';
import 'product_prefix_provider.dart';
import 'scoped_pref_codec.dart';

class ScopedPref<T> extends Notifier<T?> {
  ScopedPref({required this.rawKey, required this.codec, this.onLocalSet})
      : assert(rawKey.isNotEmpty, 'rawKey must be non-empty');

  final String rawKey;
  final ScopedPrefCodec<T> codec;
  final FutureOr<void> Function(T value)? onLocalSet;

  late String _scope;
  bool _hydrated = false;
  Future<void>? _hydrating;
  int _buildEpoch = 0;
  late String _productPrefix;

  T? get value => state;

  @override
  T? build() {
    _productPrefix = ref.watch(productPrefixProvider);
    _scope = ref.watch(currentAccountScopeProvider);
    _hydrated = false;
    _hydrating = null;
    _buildEpoch += 1;
    final epoch = _buildEpoch;
    Future.microtask(() {
      if (!ref.mounted || _buildEpoch != epoch) return;
      ensureHydrated();
    });
    return null;
  }

  Future<void> ensureHydrated() {
    if (_hydrated) return Future<void>.value();
    final epoch = _buildEpoch;
    return _hydrating ??= _hydrate(epoch).whenComplete(() {
      if (_buildEpoch == epoch) _hydrating = null;
    });
  }

  Future<void> set(T v) async {
    final didPersist = await _write(v);
    if (didPersist) await onLocalSet?.call(v);
  }

  Future<void> setFromSync(T v) {
    return _write(v);
  }

  Future<bool> _write(T value) async {
    await _ensureCurrentScopeHydrated();
    if (!ref.mounted) return false;
    final epoch = _buildEpoch;
    final key = _key();
    final encoded = codec.encode(value);
    final prefs = await _sharedPreferences();
    if (!ref.mounted || _buildEpoch != epoch) return false;
    state = value;
    await prefs.setString(key, encoded);
    return ref.mounted && _buildEpoch == epoch;
  }

  Future<void> _ensureCurrentScopeHydrated() async {
    while (ref.mounted) {
      final epoch = _buildEpoch;
      await ensureHydrated();
      if (!ref.mounted) return;
      if (_buildEpoch == epoch && _hydrated) return;
    }
  }

  Future<void> _hydrate(int epoch) async {
    final key = _key();
    final prefs = await _sharedPreferences();
    final raw = prefs.getString(key);
    T? next;
    if (raw != null && raw.isNotEmpty) {
      try {
        next = codec.decode(raw);
      } catch (_) {
        next = null;
      }
    }
    if (!ref.mounted || _buildEpoch != epoch) return;
    state = next;
    _hydrated = true;
  }

  String _key() =>
      scopedKey(productPrefix: _productPrefix, scope: _scope, rawKey: rawKey);

  /// Delegate to `SharedPreferences.getInstance()`. The plugin already
  /// caches the resolved instance internally, and `setMockInitialValues({})`
  /// in tests properly resets it — caching here would mask that reset and
  /// silently leak state across tests (see W2c-2 regression analysis).
  static Future<SharedPreferences> _sharedPreferences() =>
      SharedPreferences.getInstance();

  @visibleForTesting
  static void resetForTesting() {
    // No-op: instance is owned by the SharedPreferences plugin's own
    // internal cache, which `SharedPreferences.setMockInitialValues({})`
    // resets directly. Kept for backward source compatibility with
    // tests that already call this helper.
  }
}
