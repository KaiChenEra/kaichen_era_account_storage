import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaichen_era_account_storage/kaichen_era_account_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _stringCodec = ScopedPrefCodec<String>(
  encode: (value) => value,
  decode: (raw) => raw,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ScopedPref.resetForTesting();
  });

  test('hydrates on first read', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lectio.anon.demo': 'persisted',
    });

    final provider = _stringPrefProvider();
    final container = _container();

    expect(container.read(provider), isNull);

    await container.read(provider.notifier).ensureHydrated();

    expect(container.read(provider), 'persisted');
    expect(container.read(provider.notifier).value, 'persisted');
  });

  test('concurrent hydrate calls share one Future', () async {
    var decodeCount = 0;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lectio.anon.demo': 'persisted',
    });

    final provider = _stringPrefProvider(
      codec: ScopedPrefCodec<String>(
        encode: (value) => value,
        decode: (raw) {
          decodeCount += 1;
          return raw;
        },
      ),
    );
    final controller = _container().read(provider.notifier);

    final first = controller.ensureHydrated();
    final second = controller.ensureHydrated();

    expect(identical(first, second), isTrue);

    await Future.wait(<Future<void>>[first, second]);

    expect(controller.value, 'persisted');
    expect(decodeCount, 1);
  });

  test('set updates value and persists with scoped key', () async {
    final provider = _stringPrefProvider();
    final container = _container();
    final controller = container.read(provider.notifier);

    await controller.set('local');

    final prefs = await SharedPreferences.getInstance();
    expect(container.read(provider), 'local');
    expect(prefs.getString('lectio.anon.demo'), 'local');
    expect(prefs.getString('demo'), isNull);
  });

  test('product prefix override namespaces persisted key', () async {
    final provider = _stringPrefProvider();
    final container = _container(productPrefix: 'ariya');
    final controller = container.read(provider.notifier);

    await controller.set('local');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ariya.anon.demo'), 'local');
    expect(prefs.getString('lectio.anon.demo'), isNull);
  });

  test('setFromSync updates without invoking local-set hook', () async {
    final localSets = <String>[];
    final provider = _stringPrefProvider(onLocalSet: localSets.add);
    final container = _container();
    final controller = container.read(provider.notifier);

    await controller.set('local');
    await controller.setFromSync('remote');

    final prefs = await SharedPreferences.getInstance();
    expect(controller.value, 'remote');
    expect(prefs.getString('lectio.anon.demo'), 'remote');
    expect(localSets, <String>['local']);
  });

  test('account scope flip rebuilds and rehydrates from new scope', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lectio.anon.demo': 'anonymous',
      'lectio.user-u-1.demo': 'signed-in',
    });

    final provider = _stringPrefProvider();
    var scope = anonScope;
    final container = _container(scope: () => scope);

    await container.read(provider.notifier).ensureHydrated();
    expect(container.read(provider), 'anonymous');

    scope = 'user-u-1';
    container.invalidate(currentAccountScopeProvider);

    expect(container.read(provider), isNull);

    await container.read(provider.notifier).ensureHydrated();
    expect(container.read(provider), 'signed-in');
  });

  test(
    'resetForTesting clears the cached SharedPreferences instance',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'lectio.anon.demo': 'before-reset',
      });

      final firstProvider = _stringPrefProvider();
      final firstContainer = _container();
      await firstContainer.read(firstProvider.notifier).ensureHydrated();
      expect(firstContainer.read(firstProvider), 'before-reset');

      SharedPreferences.setMockInitialValues(<String, Object>{
        'lectio.anon.demo': 'after-reset',
      });
      ScopedPref.resetForTesting();

      final secondProvider = _stringPrefProvider();
      final secondContainer = _container();
      await secondContainer.read(secondProvider.notifier).ensureHydrated();

      expect(secondContainer.read(secondProvider), 'after-reset');
    },
  );
}

NotifierProvider<ScopedPref<String>, String?> _stringPrefProvider({
  String rawKey = 'demo',
  ScopedPrefCodec<String>? codec,
  FutureOr<void> Function(String value)? onLocalSet,
}) {
  return NotifierProvider<ScopedPref<String>, String?>(
    () => ScopedPref<String>(
      rawKey: rawKey,
      codec: codec ?? _stringCodec,
      onLocalSet: onLocalSet,
    ),
  );
}

ProviderContainer _container({
  String Function()? scope,
  String productPrefix = 'lectio',
}) {
  final container = ProviderContainer(
    overrides: [
      productPrefixProvider.overrideWithValue(productPrefix),
      currentAccountScopeProvider.overrideWith((ref) {
        return scope?.call() ?? anonScope;
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
