import 'system_metrics.dart';

/// /proc erişimi olmayan platformlarda (ör. web) boş değer döner.
Future<SystemMetrics> readSystemMetrics() async => const SystemMetrics();
