import 'package:flutter/material.dart';

const Map<String, String> _entities = {
  '&nbsp;': ' ',
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&hellip;': '…',
  '&mdash;': '—',
  '&ndash;': '–',
};

String _decode(String input) {
  var out = input;
  _entities.forEach((k, v) => out = out.replaceAll(k, v));
  return out;
}

/// HTML içeriği okunabilir düz metne çevirir (liste önizlemesi/arama için).
String htmlToPlainText(String html) {
  if (html.trim().isEmpty) return '';
  var text = html;
  text = text.replaceAll(
      RegExp(r'<img[^>]*>', caseSensitive: false), ' [görsel] ');
  text = text.replaceAll(
      RegExp(r'<\s*(br|/p|/div|/li|/h[1-6])\s*/?>', caseSensitive: false),
      '\n');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  text = _decode(text);
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r'\n\s*\n+'), '\n\n');
  return text.trim();
}

/// Basit HTML -> TextSpan dönüşümü (kalın / italik / başlık / görsel).
///
/// Zengin bir HTML motoru değildir; masaüstü uygulamasının ürettiği
/// (TipTap) sade HTML içeriğini okunur biçimde göstermek içindir.
List<TextSpan> htmlToSpans(String html, {required TextStyle baseStyle}) {
  final spans = <TextSpan>[];
  final buffer = StringBuffer();
  var bold = false;
  var italic = false;
  var heading = false;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(
      text: buffer.toString(),
      style: baseStyle.copyWith(
        fontWeight: (bold || heading) ? FontWeight.bold : null,
        fontStyle: italic ? FontStyle.italic : null,
        fontSize: heading ? 18 : null,
      ),
    ));
    buffer.clear();
  }

  final tagRe = RegExp(r'<[^>]+>');
  var last = 0;
  for (final m in tagRe.allMatches(html)) {
    buffer.write(_decode(html.substring(last, m.start)));
    final tag = m.group(0)!.toLowerCase();

    if (RegExp(r'^<(strong|b)(\s|>)').hasMatch(tag)) {
      flush();
      bold = true;
    } else if (RegExp(r'^</(strong|b)>').hasMatch(tag)) {
      flush();
      bold = false;
    } else if (RegExp(r'^<(em|i)(\s|>)').hasMatch(tag)) {
      flush();
      italic = true;
    } else if (RegExp(r'^</(em|i)>').hasMatch(tag)) {
      flush();
      italic = false;
    } else if (RegExp(r'^<h[1-6](\s|>)').hasMatch(tag)) {
      flush();
      heading = true;
    } else if (RegExp(r'^</h[1-6]>').hasMatch(tag)) {
      flush();
      heading = false;
      buffer.write('\n');
    } else if (tag.startsWith('<br')) {
      buffer.write('\n');
    } else if (RegExp(r'^</(p|div|li)>').hasMatch(tag)) {
      buffer.write('\n');
    } else if (tag.startsWith('<img')) {
      buffer.write(' [görsel] ');
    }
    last = m.end;
  }
  buffer.write(_decode(html.substring(last)));
  flush();
  return spans;
}
