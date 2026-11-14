import 'transport.dart';

const bool workerSupported = false;
const String workerPlatform =
    'default Web route disabled; select OptimizationController.web explicitly';
Future<WorkerConnection> createWorker() async => throw UnsupportedError(
  'AKYS V2: Varsayılan Web yolu kapalı. Gerçek worker için OptimizationController.web ve paketlenmiş worker URL kullanın. Ana iş parçacığında arama başlatılmadı.',
);
