import 'dart:io';

import 'system_metrics.dart';

/// Android/Linux/masaüstü için gerçek cihaz metrikleri.
///
/// RAM `/proc/meminfo` üzerinden, depolama ise `df` üzerinden okunur. Her adım
/// hata durumunda 0 döner, bu yüzden eksik veri arayüzü bozmaz.
///
/// Not: `/proc/net/dev` Android 10 ve üzerinde uygulamalara kapatıldığı için
/// ağ trafiği buradan değil, `MainActivity.kt` içindeki kanaldan okunur.
Future<SystemMetrics> readSystemMetrics() async {
  final ram = await _readRam();
  final storage = await _readStorage();

  return SystemMetrics(
    ramTotal: ram.$1,
    ramFree: ram.$2,
    storageTotal: storage.$1,
    storageFree: storage.$2,
  );
}

/// (toplam bayt, boş bayt) döner.
Future<(int, int)> _readRam() async {
  try {
    final content = await File('/proc/meminfo').readAsString();
    int? total;
    int? available;

    for (final line in content.split('\n')) {
      if (line.startsWith('MemTotal:')) {
        total = _firstValueKb(line);
      } else if (line.startsWith('MemAvailable:')) {
        available = _firstValueKb(line);
      }
      if (total != null && available != null) break;
    }
    return (total ?? 0, available ?? 0);
  } catch (_) {
    return (0, 0);
  }
}

/// `/proc/meminfo` satırındaki ilk değeri (kB) bayta çevirir.
int _firstValueKb(String line) {
  final fields = line.split(RegExp(r'\s+'));
  final kb = int.tryParse(fields.length > 1 ? fields[1] : '') ?? 0;
  return kb * 1024;
}

/// (toplam bayt, boş bayt) döner.
Future<(int, int)> _readStorage() async {
  for (final path in const ['/data', '/storage/emulated/0', '/']) {
    final parsed = await _df(path);
    if (parsed != null) return parsed;
  }
  return (0, 0);
}

Future<(int, int)?> _df(String path) async {
  final candidates = <List<String>>[
    ['df', '-k', path],
    ['/system/bin/df', '-k', path],
    ['/system/bin/toybox', 'df', '-k', path],
  ];

  for (final command in candidates) {
    try {
      final result = await Process.run(command.first, command.sublist(1));
      if (result.exitCode != 0) continue;
      final parsed = _parseDf(result.stdout.toString());
      if (parsed != null) return parsed;
    } catch (_) {
      // Sıradaki adayı dene.
    }
  }
  return null;
}

/// `df -k` çıktısının son satırını ayrıştırır:
/// `Filesystem 1K-blocks Used Available Use% Mounted on`.
(int, int)? _parseDf(String output) {
  final lines = output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length < 2) return null;

  final fields = lines.last.split(RegExp(r'\s+'));
  if (fields.length < 4) return null;

  final totalKb = int.tryParse(fields[1]);
  final freeKb = int.tryParse(fields[3]);
  if (totalKb == null || freeKb == null) return null;

  return (totalKb * 1024, freeKb * 1024);
}
