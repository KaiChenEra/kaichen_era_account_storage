import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaichen_era_account_storage/kaichen_era_account_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _stringCodec =
    ScopedPrefCodec<String>(encode: (value) => value, decode: (raw) => raw);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ScopedPref.resetForTesting();
  });

  test('local set enqueues a CloudKit pref push', () async {
    final provider = _syncedStringPrefProvider();
    final container = _container();
    final controller = container.read(provider.notifier);

    await controller.set('local');

    final queue = container.read(_demoPushQueueProvider);
    expect(queue.snapshot, hasLength(1));
    expect(queue.snapshot.single.kind, _DemoPushOpKind.pushPref);
    expect(queue.snapshot.single.type, 'Pref');
    expect(queue.snapshot.single.name, 'demo_pref');
    expect(queue.snapshot.single.data, jsonEncode({'value': 'local'}));
    expect(queue.snapshot.single.opId, startsWith('pref-demo-pref-'));
  });

  test('setFromSync updates local value without enqueueing a push', () async {
    final provider = _syncedStringPrefProvider();
    final container = _container();
    final controller = container.read(provider.notifier);

    await controller.set('local');
    final queue = container.read(_demoPushQueueProvider);
    final queuedBeforeSync = queue.snapshot.length;

    await controller.setFromSync('remote');

    final prefs = await SharedPreferences.getInstance();
    expect(container.read(provider), 'remote');
    expect(prefs.getString('lectio.anon.demo'), 'remote');
    expect(queue.snapshot, hasLength(queuedBeforeSync));
    expect(queue.snapshot.single.data, jsonEncode({'value': 'local'}));
  });

  test('scope change writes and pushes the new scope value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lectio.anon.demo': 'anonymous-stale',
      'lectio.user-u-1.demo': 'signed-in-before'
    });

    final provider = _syncedStringPrefProvider();
    var scope = anonScope;
    final container = _container(scope: () => scope);

    await container.read(provider.notifier).ensureHydrated();
    expect(container.read(provider), 'anonymous-stale');

    scope = 'user-u-1';
    container.invalidate(currentAccountScopeProvider);

    await container.read(provider.notifier).set('signed-in-fresh');

    final prefs = await SharedPreferences.getInstance();
    final queue = container.read(_demoPushQueueProvider);
    expect(prefs.getString('lectio.anon.demo'), 'anonymous-stale');
    expect(prefs.getString('lectio.user-u-1.demo'), 'signed-in-fresh');
    expect(queue.scope, 'user-u-1');
    expect(
        queue.snapshot.single.data, jsonEncode({'value': 'signed-in-fresh'}));
  });

  test('syncEncoder receives each latest set value', () async {
    final encodedValues = <String>[];
    final provider = _syncedStringPrefProvider(
      syncEncoder: (value) {
        encodedValues.add(value);
        return {'value': value};
      },
    );
    final container = _container();
    final controller = container.read(provider.notifier);

    final first = controller.set('first');
    final second = controller.set('second');
    await Future.wait(<Future<void>>[first, second]);

    final data = container
        .read(_demoPushQueueProvider)
        .snapshot
        .map((op) => jsonDecode(op.data) as Map<String, dynamic>)
        .map((json) => json['value'])
        .toList();
    expect(encodedValues, <String>['first', 'second']);
    expect(data, <String>['first', 'second']);
  });

  test('set before hydrate completes hydrates and persists before push',
      () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'lectio.anon.demo': 'persisted-before'});
    final events = <String>[];
    final prefs = await SharedPreferences.getInstance();
    final provider = _syncedStringPrefProvider(
      codec: ScopedPrefCodec<String>(
        encode: (value) {
          events.add('encode:$value');
          return value;
        },
        decode: (raw) {
          events.add('decode:$raw');
          return raw;
        },
      ),
      syncEncoder: (value) {
        events.add('push:${prefs.getString('lectio.anon.demo')}');
        return {'value': value};
      },
    );
    final container = _container();
    final controller = container.read(provider.notifier);

    await controller.set('local-before-hydrate');

    expect(events, <String>[
      'decode:persisted-before',
      'encode:local-before-hydrate',
      'push:local-before-hydrate'
    ]);
    expect(container.read(_demoPushQueueProvider).snapshot.single.data,
        jsonEncode({'value': 'local-before-hydrate'}));
  });
}

NotifierProvider<ScopedSyncedPref<String>, String?> _syncedStringPrefProvider({
  String rawKey = 'demo',
  ScopedPrefCodec<String>? codec,
  Map<String, dynamic> Function(String value)? syncEncoder,
  FutureOr<void> Function(String value)? onLocalSet,
  ScopedSyncedPrefEnqueuePush? enqueuePush,
}) {
  return NotifierProvider<ScopedSyncedPref<String>, String?>(
    () => ScopedSyncedPref<String>(
      rawKey: rawKey,
      codec: codec ?? _stringCodec,
      cloudKitPrefName: 'demo_pref',
      cloudKitRecordType: 'Pref',
      syncEncoder: syncEncoder ?? ((value) => {'value': value}),
      enqueuePush: enqueuePush ?? _enqueueDemoPrefPush,
      onLocalSet: onLocalSet,
    ),
  );
}

Future<void> _enqueueDemoPrefPush({
  required Ref ref,
  required String opId,
  required String recordType,
  required String recordName,
  required String data,
}) async {
  ref.read(_demoPushQueueProvider).enqueueAndPersist(_DemoPushOp(
      opId: opId,
      kind: _DemoPushOpKind.pushPref,
      type: recordType,
      name: recordName,
      data: data));
}

enum _DemoPushOpKind { pushPref }

class _DemoPushOp {
  const _DemoPushOp({
    required this.opId,
    required this.kind,
    required this.type,
    required this.name,
    required this.data,
  });

  final String opId;
  final _DemoPushOpKind kind;
  final String type;
  final String name;
  final String data;
}

class _DemoPushQueue {
  _DemoPushQueue({required this.scope});

  final String scope;
  final List<_DemoPushOp> _snapshot = [];

  List<_DemoPushOp> get snapshot => List.unmodifiable(_snapshot);

  void enqueueAndPersist(_DemoPushOp op) {
    _snapshot.add(op);
  }
}

final _demoPushQueueProvider = Provider<_DemoPushQueue>((ref) {
  return _DemoPushQueue(scope: ref.watch(currentAccountScopeProvider));
});

ProviderContainer _container({String Function()? scope}) {
  final container = ProviderContainer(
    overrides: [
      currentAccountScopeProvider.overrideWith((ref) {
        return scope?.call() ?? anonScope;
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
