import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kullanıcının seçtiği bir metin dosyası.
class PickedFile {
  final String name;
  final String content;

  /// 15 MB sınırı aşıldığı için içerik kesildiyse `true`.
  final bool truncated;

  PickedFile({
    required this.name,
    required this.content,
    this.truncated = false,
  });
}

/// Cihazın bir ses çıkış aygıtı (hoparlör, kulaklık, bluetooth...).
class AudioOutput {
  final String name;
  final int type;

  AudioOutput({required this.name, required this.type});
}

/// Android Storage Access Framework (SAF) üzerinden dosya seçme/kaydetme
/// köprüsü. (`MainActivity.kt` -> "ultimate_mobile/files" kanalı)
///
/// Böylece geniş depolama izni (MANAGE_EXTERNAL_STORAGE) istemeden,
/// kullanıcının kendi seçtiği konuma dosya yazıp okuyabiliyoruz.
class FileIo {
  static const MethodChannel _channel = MethodChannel('ultimate_mobile/files');

  /// Kullanıcıya bir metin/liste dosyası seçtirir. İptal edilirse `null`.
  Future<PickedFile?> pickTextFile() async {
    try {
      final res = await _channel.invokeMethod<dynamic>('pickTextFile');
      if (res is! Map) return null;
      return PickedFile(
        name: (res['name'] ?? 'dosya').toString(),
        content: (res['content'] ?? '').toString(),
        truncated: res['truncated'] == true,
      );
    } on PlatformException catch (e) {
      debugPrint('Dosya seçilemedi: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// İçeriği kullanıcının seçtiği konuma kaydeder. Kaydedilen adı döner,
  /// iptal edilirse `null`.
  Future<String?> saveTextFile({
    required String name,
    required String content,
    String mime = 'text/plain',
  }) async {
    try {
      final res = await _channel.invokeMethod<dynamic>('saveTextFile', {
        'name': name,
        'content': content,
        'mime': mime,
      });
      if (res is! Map) return null;
      return (res['name'] ?? name).toString();
    } on PlatformException catch (e) {
      debugPrint('Dosya kaydedilemedi: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Kullanıcıya galeriden bir görsel seçtirir. Seçilen görsel uygulamanın
  /// özel klasörüne kopyalanır ve **yerel dosya yolu** döner. İptal edilirse
  /// `null`.
  Future<String?> pickImage() async {
    try {
      final res = await _channel.invokeMethod<dynamic>('pickImage');
      if (res is! String || res.isEmpty) return null;
      return res;
    } on PlatformException catch (e) {
      debugPrint('Görsel seçilemedi: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Cihazın kullanılabilir ses çıkış aygıtları.
  Future<List<AudioOutput>> audioOutputs() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('getAudioDevices');
      if (res == null) return const [];
      return res
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (m) => AudioOutput(
              name: (m['name'] ?? 'Aygıt').toString(),
              type: (m['type'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();
    } on PlatformException catch (e) {
      debugPrint('Çıkış aygıtları alınamadı: ${e.message}');
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
