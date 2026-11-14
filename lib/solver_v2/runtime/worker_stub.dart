import 'transport.dart';

const bool workerSupported = false;
const String workerPlatform = 'unsupported: no verified Web Worker backend';
Future<WorkerConnection> createWorker() async => throw UnsupportedError(
  'AKYS V2: Bu platformda doğrulanmış arka plan worker desteği yok. Ana iş parçacığında arama başlatılmadı.',
);
