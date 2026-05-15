import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Product prefix for key namespacing inside `kaichen_era_account_storage`.
///
/// Each suite app (lectio, ariya, ...) MUST override this provider at boot:
/// ```dart
/// ProviderScope(
///   overrides: [
///     productPrefixProvider.overrideWithValue('lectio'),
///   ],
///   child: const LectioApp(),
/// );
/// ```
///
/// Default value 'lectio' is for backward compat only; relying on it in
/// production is a bug -- it will collide when a 2nd suite app uses this
/// package.
final productPrefixProvider = Provider<String>((ref) {
  return 'lectio'; // default for backward compat
});
