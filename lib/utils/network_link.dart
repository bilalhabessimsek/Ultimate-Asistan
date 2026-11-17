import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Aktif bağlantının türü, tahmini bağlantı hızı ve trafik sayaçları.
///
/// `android/.../MainActivity.kt` içindeki `ultimate_mobile/network` kanalı
/// ConnectivityManager ve TrafficStats üzerinden beslenir.
class NetworkLink {
  /// wifi, mobile, ethernet, vpn, other veya none.
  final String type;

  /// Bağlantının tahmini indirme bant genişliği (Kbps).
  final int downKbps;

  /// Bağlantının tahmini yükleme bant genişliği (Kbps).
  final int upKbps;

  /// Cihazın açılışından bu yana toplam indirilen veri (bayt, kümülatif).
  final int rxBytes;

  /// Cihazın açılışından bu yana toplam gönderilen veri (bayt, kümülatif).
  final int txBytes;

  const NetworkLink({
    this.type = 'none',
    this.downKbps = 0,
    this.upKbps = 0,
    this.rxBytes = 0,
    this.txBytes = 0,
  });

  /// Mbps cinsinden bağlantı hızı.
  double get downMbps => downKbps / 1000.0;

  bool get isConnected => type != 'none';
}

const MethodChannel _channel = MethodChannel('ultimate_mobile/network');

/// Bağlantı bilgisini okur. Kanal yoksa (masaüstü/web) nötr değer döner.
Future<NetworkLink> readNetworkLink() async {
  try {
    final map =
        await _channel.invokeMethod<Map<dynamic, dynamic>>('getLinkInfo');
    if (map == null) return const NetworkLink();
    return NetworkLink(
      type: (map['type'] ?? 'none').toString(),
      downKbps: (map['downKbps'] as num?)?.toInt() ?? 0,
      upKbps: (map['upKbps'] as num?)?.toInt() ?? 0,
      rxBytes: (map['rxBytes'] as num?)?.toInt() ?? 0,
      txBytes: (map['txBytes'] as num?)?.toInt() ?? 0,
    );
  } on PlatformException catch (err) {
    debugPrint('Bağlantı bilgisi okunamadı: ${err.message}');
    return const NetworkLink();
  } on MissingPluginException {
    return const NetworkLink();
  }
}
