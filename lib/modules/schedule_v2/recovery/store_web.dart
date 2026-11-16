import 'dart:js_interop';

import 'store.dart';

@JS('akysRecovery.read')
external JSPromise<JSAny?> _read(JSString owner);
@JS('akysRecovery.write')
external JSPromise<JSAny?> _write(JSString owner, JSString plaintext);
@JS('akysRecovery.remove')
external JSPromise<JSAny?> _remove(JSString owner);
RecoveryStore createStore() => _WebStore();

class _WebStore implements RecoveryStore {
  @override
  Future<String?> read(String owner) async =>
      ((await _read(owner.toJS).toDart) as JSString?)?.toDart;
  @override
  Future<void> write(String owner, String plaintext) async {
    await _write(owner.toJS, plaintext.toJS).toDart;
  }

  @override
  Future<void> delete(String owner) async {
    await _remove(owner.toJS).toDart;
  }
}
