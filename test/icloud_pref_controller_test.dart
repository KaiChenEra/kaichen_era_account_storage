import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaichen_era_account_storage/kaichen_era_account_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mutable tier holder for the test source.
class _TierNotifier extends Notifier<EntitlementTier> {
  @override
  EntitlementTier build() => EntitlementTier.free;

  // ignore: use_setters_to_change_properties
  void set(EntitlementTier tier) => state = tier;
}

final _tierProvider =
    NotifierProvider<_TierNotifier, EntitlementTier>(_TierNotifier.new);

class _FakeTierSource implements EntitlementTierSource {
  @override
  EntitlementTier readTier(Ref ref) => ref.read(_tierProvider);

  @override
  void listenTier(
    Ref ref,
    void Function(EntitlementTier? previous, EntitlementTier next) onFlip,
  ) {
    ref.listen<EntitlementTier>(_tierProvider, (prev, next) {
      onFlip(prev, next);
    });
  }
}

class _FakePrefSet implements ICloudPrefSet {
  @override
  String get productPrefix => 'lectio';

  @override
  List<ScopedPref<dynamic>> get prefs => const <ScopedPref<dynamic>>[];
}

class _TestICloudPrefController extends ICloudPrefController {
  _TestICloudPrefController()
      : super(prefSet: _FakePrefSet(), tierSource: _FakeTierSource());

  @override
  String get toggleRawKey => 'icloud_sync_test';
}

final _testProvider =
    NotifierProvider<_TestICloudPrefController, ICloudPrefState>(
  _TestICloudPrefController.new,
);

ProviderContainer _newContainer() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

Future<ICloudPrefState> _waitHydrated(
  ProviderContainer container,
  NotifierProvider<_TestICloudPrefController, ICloudPrefState> provider,
) async {
  await container.read(provider.notifier).hydrate();
  return container.read(provider);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ScopedPref.resetForTesting();
  });

  test('initial state is enabled=false, userSet=false', () async {
    final container = _newContainer();
    final state = await _waitHydrated(container, _testProvider);
    expect(state.enabled, isFalse);
    expect(state.userSet, isFalse);
    expect(state.hydrated, isTrue);
  });

  test('hydrates persisted state from the per-account scope', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lectio.anon.icloud_sync_test':
          '{"enabled":true,"userSet":true}',
    });

    final container = _newContainer();
    final state = await _waitHydrated(container, _testProvider);
    expect(state.enabled, isTrue);
    expect(state.userSet, isTrue);
  });

  test('user-initiated setEnabled flips userSet sticky to true', () async {
    final container = _newContainer();
    await _waitHydrated(container, _testProvider);

    await container.read(_testProvider.notifier).setEnabled(true);
    final after = container.read(_testProvider);
    expect(after.enabled, isTrue);
    expect(after.userSet, isTrue);
  });

  test('tier flip free → pro auto-toggles enabled while userSet=false',
      () async {
    final container = _newContainer();
    await _waitHydrated(container, _testProvider);
    expect(container.read(_testProvider).enabled, isFalse);

    container.read(_tierProvider.notifier).set(EntitlementTier.pro);
    // Drain microtasks (setEnabled is unawaited inside _onTierFlip).
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final after = container.read(_testProvider);
    expect(after.enabled, isTrue);
    expect(after.userSet, isFalse,
        reason: 'auto-toggle must not flip the sticky bit');
  });

  test('tier flip pro → free auto-toggles enabled off (sticky=false)',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lectio.anon.icloud_sync_test':
          '{"enabled":true,"userSet":false}',
    });
    final container = _newContainer();
    container.read(_tierProvider.notifier).set(EntitlementTier.pro);
    await _waitHydrated(container, _testProvider);
    expect(container.read(_testProvider).enabled, isTrue);

    container.read(_tierProvider.notifier).set(EntitlementTier.free);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(_testProvider).enabled, isFalse);
  });

  test('tier flip does NOT touch enabled once userSet=true', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lectio.anon.icloud_sync_test':
          '{"enabled":false,"userSet":true}',
    });
    final container = _newContainer();
    await _waitHydrated(container, _testProvider);

    container.read(_tierProvider.notifier).set(EntitlementTier.pro);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final after = container.read(_testProvider);
    expect(after.enabled, isFalse, reason: 'sticky userSet wins over tier');
    expect(after.userSet, isTrue);
  });

  test('markSynced records lastSyncAt timestamp', () async {
    final container = _newContainer();
    await _waitHydrated(container, _testProvider);

    final at = DateTime.utc(2026, 5, 19, 12, 0, 0);
    await container.read(_testProvider.notifier).markSynced(at);

    expect(container.read(_testProvider).lastSyncAt, at);
  });

  test('persisted toggle round-trips through codec', () async {
    final container = _newContainer();
    await _waitHydrated(container, _testProvider);
    await container.read(_testProvider.notifier).setEnabled(true);

    // Build a fresh container to force a re-read from SharedPreferences.
    final container2 = _newContainer();
    final reloaded = await _waitHydrated(container2, _testProvider);
    expect(reloaded.enabled, isTrue);
    expect(reloaded.userSet, isTrue);
  });

  test('ICloudPrefState equality and copyWith preserve identity semantics',
      () {
    const a = ICloudPrefState(
      enabled: true,
      userSet: true,
      hydrated: true,
    );
    final b = a.copyWith();
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);

    final c = a.copyWith(enabled: false);
    expect(a == c, isFalse);
  });

  test('ICloudPrefState JSON round-trip includes lastSyncAt', () {
    final original = ICloudPrefState(
      enabled: true,
      userSet: true,
      hydrated: true,
      lastSyncAt: DateTime.utc(2026, 5, 19, 12, 0, 0),
    );
    final json = original.toJson();
    final decoded = ICloudPrefState.fromJson(json);
    expect(decoded.enabled, isTrue);
    expect(decoded.userSet, isTrue);
    expect(decoded.lastSyncAt, original.lastSyncAt);
  });
}
