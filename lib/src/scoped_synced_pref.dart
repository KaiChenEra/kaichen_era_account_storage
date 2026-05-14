/// Generic account-scoped + CloudKit-synced SharedPreferences facade.
///
/// Extends [ScopedPref] with automatic push enqueue on local writes through
/// [set]. Remote-originated writes go through inherited [setFromSync], which
/// only persists local state and does not enqueue another push.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scoped_pref.dart';

typedef ScopedSyncedPrefEnqueuePush = FutureOr<void> Function(
    {required Ref ref,
    required String opId,
    required String recordType,
    required String recordName,
    required String data});

class ScopedSyncedPref<T> extends ScopedPref<T> {
  ScopedSyncedPref({
    required super.rawKey,
    required super.codec,
    required this.cloudKitPrefName,
    required this.cloudKitRecordType,
    required this.syncEncoder,
    required this.enqueuePush,
    super.onLocalSet,
  });

  /// CloudKit record name for this preference, for example `engine_config`.
  final String cloudKitPrefName;

  /// CloudKit record type for preference records, usually `Pref`.
  final String cloudKitRecordType;

  /// Encodes the sync payload. This may intentionally differ from the
  /// SharedPreferences storage codec.
  final Map<String, dynamic> Function(T value) syncEncoder;

  /// Enqueues the serialized CloudKit push operation.
  ///
  /// The concrete queue lives in the host app; keeping it behind this
  /// callback preserves this package as a feature-agnostic layer.
  final ScopedSyncedPrefEnqueuePush enqueuePush;

  @override
  Future<void> set(T v) async {
    await super.set(v);
    // `ref.mounted` is the scope-change signal: when the account scope
    // changes mid-write, the Notifier rebuilds and `ref` becomes unmounted —
    // do not enqueue a push for the stale scope's value. We intentionally
    // do NOT guard on `value != v` (that would drop legitimate rapid-fire
    // back-to-back writes); each call to `set()` is a discrete user action
    // and earns its own push op.
    if (!ref.mounted) return;

    final data = jsonEncode(syncEncoder(v));
    if (!ref.mounted) return;

    await enqueuePush(
        ref: ref,
        opId: _opId(),
        recordType: cloudKitRecordType,
        recordName: cloudKitPrefName,
        data: data);
  }

  String _opId() {
    final normalizedName = cloudKitPrefName.replaceAll('_', '-');
    return 'pref-$normalizedName-${DateTime.now().millisecondsSinceEpoch}';
  }
}
