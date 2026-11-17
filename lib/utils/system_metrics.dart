import 'system_metrics_stub.dart' if (dart.library.io) 'system_metrics_io.dart'
    as impl;

/// Cihazdan okunan anlık sistem metrikleri (tüm değerler bayt cinsinden).
class SystemMetrics {
  /// Toplam RAM.
  final int ramTotal;

  /// Kullanılabilir (boş) RAM.
  final int ramFree;

  /// Toplam depolama alanı.
  final int storageTotal;

  /// Boş depolama alanı.
  final int storageFree;

  const SystemMetrics({
    this.ramTotal = 0,
    this.ramFree = 0,
    this.storageTotal = 0,
    this.storageFree = 0,
  });

  /// 0..1 arası RAM kullanım oranı.
  double get ramUsedRatio =>
      ramTotal <= 0 ? 0 : ((ramTotal - ramFree) / ramTotal).clamp(0.0, 1.0);

  /// 0..1 arası depolama kullanım oranı.
  double get storageUsedRatio => storageTotal <= 0
      ? 0
      : ((storageTotal - storageFree) / storageTotal).clamp(0.0, 1.0);
}

/// RAM ve depolama bilgisini okur.
///
/// Ağ trafiği buradan değil, `network_link.dart` içindeki kanaldan gelir.
Future<SystemMetrics> readSystemMetrics() => impl.readSystemMetrics();
