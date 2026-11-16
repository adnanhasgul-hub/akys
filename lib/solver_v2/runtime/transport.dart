/// Internal process transport. The controller never accepts caller-supplied events.
abstract interface class WorkerConnection {
  Stream<Map<String, Object?>> get events;
  void send(Map<String, Object?> command);
  Future<void> terminate();
}
