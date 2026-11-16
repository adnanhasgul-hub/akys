import 'store_native.dart'
    if (dart.library.js_interop) 'store_web.dart'
    as platform;

/// Ciphertext-only durable storage. Platform keys never enter Dart messages.
abstract interface class RecoveryStore {
  Future<String?> read(String owner);
  Future<void> write(String owner, String plaintext);
  Future<void> delete(String owner);
}

RecoveryStore createRecoveryStore() => platform.createStore();
