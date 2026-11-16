import 'package:flutter/services.dart';

import 'store.dart';

RecoveryStore createStore() => _NativeStore();

class _NativeStore implements RecoveryStore {
  static const channel = MethodChannel('akys/recovery');
  @override
  Future<String?> read(String owner) =>
      channel.invokeMethod<String>('read', {'owner': owner});
  @override
  Future<void> write(String owner, String plaintext) => channel
      .invokeMethod<void>('write', {'owner': owner, 'plaintext': plaintext});
  @override
  Future<void> delete(String owner) =>
      channel.invokeMethod<void>('delete', {'owner': owner});
}
