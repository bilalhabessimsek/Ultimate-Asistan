import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ultimate_mobile/screens/calendar_screen.dart';
import 'package:ultimate_mobile/utils/text_utils.dart';

void main() {
  group('htmlToPlainText', () {
    test('etiketleri temizler ve düz metin döndürür', () {
      expect(htmlToPlainText('<p>Merhaba <strong>dünya</strong></p>'),
          'Merhaba dünya');
    });

    test('paragraf sonlarını satıra çevirir', () {
      final text = htmlToPlainText('<p>Bir</p><p>İki</p>');
      expect(text, 'Bir\nİki');
    });

    test('görselleri [görsel] olarak işaretler', () {
      expect(htmlToPlainText('<p>a</p><img src="x.png" />'),
          'a\n [görsel]');
    });

    test('html entity karakterlerini çözer', () {
      expect(htmlToPlainText('<p>a &amp; b &lt;c&gt;</p>'), 'a & b <c>');
    });

    test('bos icerikte bos string dondurur', () {
      expect(htmlToPlainText('   '), '');
    });
  });

  group('htmlToSpans', () {
    test('kalın metin için FontWeight.bold üretir', () {
      final spans = htmlToSpans(
        '<strong>x</strong>',
        baseStyle: const TextStyle(),
      );
      expect(spans.any((s) => s.style?.fontWeight == FontWeight.bold), true);
    });

    test('italik metin için FontStyle.italic üretir', () {
      final spans = htmlToSpans(
        '<em>x</em>',
        baseStyle: const TextStyle(),
      );
      expect(spans.any((s) => s.style?.fontStyle == FontStyle.italic), true);
    });
  });

  group('formatDateKey', () {
    test('masaustu ile ayni sifir dolgusuz bicimi uretir', () {
      expect(formatDateKey(DateTime(2026, 10, 5)), '2026-10-5');
      expect(formatDateKey(DateTime(2026, 1, 1)), '2026-1-1');
    });
  });
}
