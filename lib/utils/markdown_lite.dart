/// Küçük, harici paketsiz bir not biçimlendirme katmanı.
///
/// Not içeriği artık **ham HTML yerine düz metin (markdown)** olarak
/// girilir ve saklanır:
///   `# Başlık`, `## Alt başlık`, `**kalın**`, `*italik*`,
///   `- madde`, `![görsel](/yol/dosya.jpg)`
///
/// Kullanıcı HTML yazmaz; araç çubuğu seçili metnin etrafına bu
/// işaretleri koyar. `renderNoteBody` bunu WYSIWYG olarak çizdirir.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import 'text_utils.dart';

/// Eski HTML içerikleri markdown'a çevrilir (geri uyumluluk için).
String htmlToMarkdown(String html) {
  if (html.trim().isEmpty) return '';
  var s = html;

  // 1) Görseller -> ![görsel](url)
  s = s.replaceAllMapped(
    RegExp(r'''<img[^>]*?src=["']([^"']*)["'][^>]*?/?>''',
        caseSensitive: false),
    (m) => '\n\n![görsel](${m[1] ?? ''})\n\n',
  );

  // 2) Başlıklar -> #, ##, ### (h4+ -> ###)
  for (var i = 1; i <= 6; i++) {
    final hashes = '#' * (i > 3 ? 3 : i);
    s = s.replaceAll(
      RegExp('<h$i[^>]*>', caseSensitive: false),
      '\n\n$hashes ',
    );
    s = s.replaceAll(RegExp('</h$i>', caseSensitive: false), '\n\n');
  }

  // 3) Paragraf / satır kırıkları
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(
    RegExp(r'</p>\s*<p[^>]*>', caseSensitive: false),
    '\n\n',
  );

  // 4) Liste öğeleri
  s = s.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n- ');

  // 5) Kalın / italik
  s = s.replaceAll(RegExp(r'</?(b|strong)>', caseSensitive: false), '**');
  s = s.replaceAll(RegExp(r'</?(i|em)>', caseSensitive: false), '*');

  // 6) Kalan tüm etiketleri sil
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');

  // 7) HTML karakter kodlarını geri çevir
  const ents = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
  };
  ents.forEach((k, v) => s = s.replaceAll(k, v));

  // 8) Gereksiz boşlukları topla (3+ boş satır -> 1 boş satır)
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return s;
}

/// Markdown'ı HTML'e çevirir (veritabanı/masaüstü uyumu için).
String markdownToHtml(String md) {
  final buf = StringBuffer();
  final lines = md.split('\n');
  var inList = false;

  void closeList() {
    if (inList) {
      buf.write('</ul>');
      inList = false;
    }
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      closeList();
      continue;
    }
    if (line.startsWith('- ') || line.startsWith('* ')) {
      if (!inList) {
        buf.write('<ul>');
        inList = true;
      }
      buf.write('<li>${_inlineToHtml(line.substring(2))}</li>');
      continue;
    }
    closeList();
    if (line.startsWith('### ')) {
      buf.write('<h3>${_inlineToHtml(line.substring(4))}</h3>');
    } else if (line.startsWith('## ')) {
      buf.write('<h2>${_inlineToHtml(line.substring(3))}</h2>');
    } else if (line.startsWith('# ')) {
      buf.write('<h1>${_inlineToHtml(line.substring(2))}</h1>');
    } else {
      buf.write('<p>${_inlineToHtml(line)}</p>');
    }
  }
  closeList();
  return buf.toString();
}

String _inlineToHtml(String s) {
  var out = s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  out = out.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'),
    (m) => '<img src="${m[2]}" alt="${m[1]}" />',
  );
  out =
      out.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => '<b>${m[1]}</b>');
  out = out.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => '<i>${m[1]}</i>');
  return out;
}

/// Liste önizlemesi/arama için içeriği (HTML ya da markdown) düz metne indirger.
String notePlainText(String raw) {
  final looksHtml = RegExp(
    r'<(p|br|div|span|b|strong|i|em|h[1-6]|ul|ol|li|img)\b',
    caseSensitive: false,
  ).hasMatch(raw);
  var text = looksHtml ? htmlToPlainText(raw) : raw;
  text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' [görsel] ');
  text = text.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!);
  text = text.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m[1]!);
  text = text.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

/// Markdown metnini WYSIWYG widget listesine çevirir.
List<Widget> renderNoteBody(String markdown, {Color accent = Colors.white}) {
  final widgets = <Widget>[];
  final lines = markdown.split('\n');
  final bullets = <String>[];

  void flushBullets() {
    if (bullets.isEmpty) return;
    widgets.add(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: bullets
            .map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ',
                          style: TextStyle(color: Colors.grey, fontSize: 15)),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: _inlineSpans(b, accent)),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 15, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    widgets.add(const SizedBox(height: 12));
    bullets.clear();
  }

  for (final raw in lines) {
    final line = raw.trimRight();

    if (line.trim().isEmpty) {
      flushBullets();
      continue;
    }

    // Tek başına bir görsel satırı
    final onlyImg =
        RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$').firstMatch(line.trim());
    if (onlyImg != null) {
      flushBullets();
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _noteImage(onlyImg[2]!, accent),
        ),
      );
      continue;
    }

    // Başlıklar
    if (line.startsWith('### ')) {
      flushBullets();
      widgets.add(_heading(line.substring(4), 17, accent));
      continue;
    }
    if (line.startsWith('## ')) {
      flushBullets();
      widgets.add(_heading(line.substring(3), 20, accent));
      continue;
    }
    if (line.startsWith('# ')) {
      flushBullets();
      widgets.add(_heading(line.substring(2), 24, accent));
      continue;
    }

    // Liste
    if (line.startsWith('- ') || line.startsWith('* ')) {
      bullets.add(line.substring(2));
      continue;
    }
    flushBullets();

    // Normal paragraf (satır içi kalın/italik/görsel)
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(
          TextSpan(children: _inlineSpans(line, accent)),
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 15,
              height: 1.6),
        ),
      ),
    );
  }
  flushBullets();
  return widgets;
}

Widget _heading(String text, double size, Color accent) {
  return Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 6),
    child: Text.rich(
      TextSpan(children: _inlineSpans(text, accent)),
      style: TextStyle(
        color: accent,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1.3,
      ),
    ),
  );
}

/// Satır içi biçimlendirmeyi parçalara ayırır (kalın/italik/görsel).
List<InlineSpan> _inlineSpans(String text, Color accent) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|!\[[^\]]*\]\([^)]+\))');
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
    }
    final tok = m.group(0)!;
    if (tok.startsWith('**')) {
      spans.add(TextSpan(
        text: tok.substring(2, tok.length - 2),
        style: TextStyle(color: accent, fontWeight: FontWeight.w700),
      ));
    } else if (tok.startsWith('![')) {
      final src = RegExp(r'\(([^)]+)\)').firstMatch(tok)?[1] ?? '';
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _noteImage(src, accent, height: 26),
      ));
    } else {
      spans.add(TextSpan(
        text: tok.substring(1, tok.length - 1),
        style:
            const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70),
      ));
    }
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

/// Yerel dosya yolundaki görseli çizer; bulunamazsa sessizce boş bırakır.
Widget _noteImage(String src, Color accent, {double? height}) {
  if (src.startsWith('http://') || src.startsWith('https://')) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        src,
        height: height ?? 220,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imgPlaceholder(accent),
      ),
    );
  }
  final file = File(src);
  if (!file.existsSync()) return _imgPlaceholder(accent);
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.file(
      file,
      height: height ?? 220,
      width: height == null ? double.infinity : null,
      fit: BoxFit.cover,
    ),
  );
}

Widget _imgPlaceholder(Color accent) {
  return Container(
    height: 90,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(Icons.broken_image_outlined, color: accent, size: 28),
  );
}
