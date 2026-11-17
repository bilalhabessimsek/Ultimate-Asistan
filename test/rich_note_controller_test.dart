import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ultimate_mobile/utils/rich_note_controller.dart';

void main() {
  group('RichNoteController — WYSIWYG not editörü', () {
    test('HTML düz metne çözülür: ekranda hiç kod/işaret yok', () {
      final c = RichNoteController()
        ..loadFromHtml(
          '<h2>Hoş Geldin!</h2>'
          '<p>Bu <b>kalın</b> ve <i>italik</i>.</p>'
          '<img src="C:/tmp/x.jpg" />',
        );

      expect(c.text, 'Hoş Geldin!\nBu kalın ve italik.');
      expect(c.text.contains('#'), isFalse);
      expect(c.text.contains('*'), isFalse);
      expect(c.text.contains('<'), isFalse);
      expect(c.images, ['C:/tmp/x.jpg']);

      final start = c.text.indexOf('Hoş');
      c.selection = TextSelection(baseOffset: start, extentOffset: start + 3);
      expect(c.activeSize, 22); // h2 -> 22 punto

      final boldStart = c.text.indexOf('kalın');
      c.selection =
          TextSelection(baseOffset: boldStart, extentOffset: boldStart + 5);
      expect(c.isBold, isTrue);
      expect(c.isItalic, isFalse);
    });

    test('kalın aç/kapa boyutu DEĞİŞTİRMEZ', () {
      final c = RichNoteController()..loadFromHtml('<p>merhaba</p>');
      final before = c.activeSize;

      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      c.toggleBold();
      expect(c.toHtml(), '<p><b>mer</b>haba</p>');
      // Aynı seçim: punto aynı kalmalı.
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      expect(c.activeSize, before);

      // Kalın kapat: boyut yine değişmemeli.
      c.toggleBold();
      expect(c.toHtml(), '<p>merhaba</p>');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      expect(c.activeSize, before);
    });

    test('sayısal punto: tüm satıra uygulanır ve h1 olarak saklanır', () {
      final c = RichNoteController()..loadFromHtml('<p>ilk satır</p>');
      c.selection = const TextSelection(baseOffset: 2, extentOffset: 2);
      c.applyFontSizeToLines(28);
      expect(c.toHtml(), '<h1>ilk satır</h1>');

      // Geri yüklenince punto korunur.
      final reopened = RichNoteController()..loadFromHtml(c.toHtml());
      expect(reopened.text, 'ilk satır');
      reopened.selection = const TextSelection(baseOffset: 1, extentOffset: 1);
      expect(reopened.activeSize, 28);
    });

    test('kısmi punto span olarak saklanır ve geri okunur', () {
      final c = RichNoteController()..loadFromHtml('<p>merhaba</p>');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      c.applyFontSize(20);
      expect(c.toHtml(), '<p><span style="font-size:20px">mer</span>haba</p>');

      final reopened = RichNoteController()..loadFromHtml(c.toHtml());
      reopened.selection = const TextSelection(baseOffset: 1, extentOffset: 1);
      expect(reopened.activeSize, 20);
    });

    test('kalın + italik birlikte', () {
      final c = RichNoteController()..loadFromHtml('<p>abc</p>');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      c.toggleBold();
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      c.toggleItalic();
      expect(c.toHtml(), '<p><b><i>abc</i></b></p>');
    });

    test('madde listesi düz metne • olarak çözülür', () {
      final c = RichNoteController()
        ..loadFromHtml('<ul><li>bir</li><li>iki</li></ul>');
      expect(c.text.trim(), '• bir\n• iki');
    });

    test('görseller HTML çıktısında not içeriğinin başında yer alır', () {
      final c = RichNoteController()..loadFromHtml('<p>yazı</p>');
      c.images.add('C:/tmp/a.png');
      final html = c.toHtml();
      expect(html.startsWith('<img src="C:/tmp/a.png" />'), isTrue);
      expect(html.indexOf('<img'), lessThan(html.indexOf('<p>')));
    });
  });
}
