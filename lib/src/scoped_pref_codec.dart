/// Codec used by [ScopedPref] to store typed values as strings.
library;

class ScopedPrefCodec<T> {
  const ScopedPrefCodec({required this.encode, required this.decode});

  final String Function(T value) encode;
  final T Function(String raw) decode;
}
