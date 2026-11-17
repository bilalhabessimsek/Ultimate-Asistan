import 'package:flutter/material.dart';

/// Not editöründe seçilebilen punto (yazı boyutu) değerleri — Word'deki gibi.
const List<double> kNoteFontSizes = [
  10,
  11,
  12,
  14,
  15,
  16,
  18,
  20,
  22,
  24,
  28,
  32,
  36,
  48,
];

/// Varsayılan punto (metin alanının temel boyutu).
const double kNoteBaseFontSize = 15;

/// Bir karakterin biçimi. **Boyut ve kalınlık ayrıdır**; kalınlığı kapatmak
/// yazıyı küçültmez.
@immutable
class CharStyle {
  final bool bold;
  final bool italic;

  /// Punto; `null` ise varsayılan ([kNoteBaseFontSize]) kullanılır.
  final double? size;

  const CharStyle({this.bold = false, this.italic = false, this.size});

  bool get isEmpty => !bold && !italic && size == null;

  double get effectiveSize => size ?? kNoteBaseFontSize;

  CharStyle copyWith(
      {bool? bold, bool? italic, double? size, bool clearSize = false}) {
    return CharStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      size: clearSize ? null : (size ?? this.size),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CharStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.size == size;

  @override
  int get hashCode => Object.hash(bold, italic, size);

  @override
  String toString() => 'CharStyle(bold: $bold, italic: $italic, size: $size)';
}

/// Gerçek WYSIWYG not editörü için zengin metin denetleyicisi.
///
/// Önemli: [text] **her zaman düz metindir** — markdown/HTML işareti
/// (`**`, `#`, `<b>` ...) ekranda GÖRÜNMEZ. Biçimler karakter başına ayrı
/// tutulur ve [buildTextSpan] ile çizilir. Böylece kullanıcı metni seçip
/// "Kalın"a bastığında yazı sadece kalınlaşır; boyut değişmez.
///
/// Kaydederken içerik `<b>`, `<i>`, `<h1..h3>`, `<span style="font-size:..">`,
/// `<p>`, `<img>` içeren HTML'e çevrilir (masaüstü uygulamasıyla aynı `notes`
/// tablosunu paylaşmak için); açılışta HTML tekrar bu modele çözülür.
class RichNoteController extends TextEditingController {
  RichNoteController();

  /// Her karakterin biçimi. Uzunluk daima `text.length`.
  List<CharStyle> _attrs = [];

  /// İmleç boşken seçilen ve bundan sonra yazılacak karakterlere uygulanacak
  /// biçim.
  CharStyle _pending = const CharStyle();

  bool _loading = false;

  /// Nota bağlı görseller — not içeriğinin ilk kısmı olarak saklanır.
  final List<String> images = [];

  // ------------------------------------------------------------------ okuma

  /// HTML (ya da düz metin) içeriği yükler.
  void loadFromHtml(String raw) {
    final parsed = _parseNoteHtml(raw);
    _loading = true;
    value = TextEditingValue(
      text: parsed.text,
      selection: TextSelection.collapsed(offset: parsed.text.length),
    );
    _attrs = parsed.attrs;
    _loading = false;
    images
      ..clear()
      ..addAll(parsed.images);
    _pending = const CharStyle();
    notifyListeners();
  }

  // ---------------------------------------------------------------- biçimler

  CharStyle _attrAt(int index) {
    if (_attrs.isEmpty || index <= 0) return const CharStyle();
    final i = index > _attrs.length ? _attrs.length : index;
    return _attrs[i - 1];
  }

  /// Seçimdeki ortak biçim (araç çubuğunu işaretlemek için).
  CharStyle get activeStyle {
    final sel = selection;
    if (!sel.isValid) return _pending;
    if (sel.isCollapsed) return _attrAt(sel.baseOffset);
    CharStyle? acc;
    for (var i = sel.start; i < sel.end && i < _attrs.length; i++) {
      if (acc == null) {
        acc = _attrs[i];
      } else if (acc != _attrs[i]) {
        // Tamamen aynı değilse ortak yönleri birleştir.
        acc = CharStyle(
          bold: acc.bold && _attrs[i].bold,
          italic: acc.italic && _attrs[i].italic,
          size: acc.size == _attrs[i].size ? acc.size : null,
        );
      }
    }
    return acc ?? const CharStyle();
  }

  bool get isBold => activeStyle.bold;
  bool get isItalic => activeStyle.italic;

  double get activeSize => activeStyle.effectiveSize;

  /// Verilen biçim değiştiricisini seçime/imlece uygular.
  void _applyToSelection(CharStyle Function(CharStyle) transform) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) {
      _pending = transform(_pending);
      notifyListeners();
      return;
    }
    var a = sel.start;
    var b = sel.end;
    if (a > b) {
      final t = a;
      a = b;
      b = t;
    }
    for (var i = a; i < b && i < _attrs.length; i++) {
      _attrs[i] = transform(_attrs[i]);
    }
    _pending = _attrAt(sel.end);
    notifyListeners();
  }

  void toggleBold() {
    final on = isBold;
    _applyToSelection((s) => s.copyWith(bold: !on));
  }

  void toggleItalic() {
    final on = isItalic;
    _applyToSelection((s) => s.copyWith(italic: !on));
  }

  /// Seçili metne punto uygular (Word'deki yazı boyutu gibi).
  void applyFontSize(double? size) {
    _applyToSelection(
      (s) =>
          size == null ? s.copyWith(clearSize: true) : s.copyWith(size: size),
    );
  }

  /// İmlecin/aralığın bulunduğu **satırların tamamına** punto uygular.
  void applyFontSizeToLines(double? size) {
    var sel = selection;
    if (!sel.isValid) {
      _pending = size == null
          ? _pending.copyWith(clearSize: true)
          : _pending.copyWith(size: size);
      notifyListeners();
      return;
    }
    var a = sel.start;
    var b = sel.end;
    if (a > b) {
      final t = a;
      a = b;
      b = t;
    }
    while (a > 0 && text.codeUnitAt(a - 1) != 10) {
      a--;
    }
    while (b < text.length && text.codeUnitAt(b) != 10) {
      b++;
    }
    for (var i = a; i < b && i < _attrs.length; i++) {
      _attrs[i] = size == null
          ? _attrs[i].copyWith(clearSize: true)
          : _attrs[i].copyWith(size: size);
    }
    _pending = _attrAt(sel.end);
    notifyListeners();
  }

  // --------------------------------------------------------------- düzenleme

  @override
  set value(TextEditingValue newValue) {
    if (!_loading) {
      final prev = super.value;
      if (newValue.text != prev.text) {
        _rebase(prev.text, newValue.text);
      } else if (!newValue.selection.isCollapsed) {
        _pending = const CharStyle();
      } else {
        _pending = _attrAt(newValue.selection.baseOffset);
      }
    }
    super.value = newValue;
  }

  /// Metin değiştiğinde biçim listesini yeni metne göre kaydırır/kırpar.
  void _rebase(String oldText, String newText) {
    final oldLen = oldText.length;
    final newLen = newText.length;
    final minLen = oldLen < newLen ? oldLen : newLen;

    var p = 0;
    while (p < minLen && oldText.codeUnitAt(p) == newText.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < minLen - p &&
        oldText.codeUnitAt(oldLen - 1 - s) ==
            newText.codeUnitAt(newLen - 1 - s)) {
      s++;
    }
    final oldEnd = (oldLen - s).clamp(0, _attrs.length);
    final insertLen = newLen - s - p;

    var inherited = const CharStyle();
    if (!_pending.isEmpty) {
      inherited = _pending;
    } else if (p > 0 && p - 1 < _attrs.length) {
      inherited = _attrs[p - 1];
    }

    final rebuilt = <CharStyle>[];
    rebuilt.addAll(_attrs.sublist(0, p.clamp(0, _attrs.length)));
    for (var i = 0; i < insertLen; i++) {
      rebuilt.add(inherited);
    }
    rebuilt.addAll(_attrs.sublist(oldEnd));

    while (rebuilt.length < newLen) {
      rebuilt.add(const CharStyle());
    }
    _attrs = rebuilt.length > newLen ? rebuilt.sublist(0, newLen) : rebuilt;
  }

  // ----------------------------------------------------------------- çizim

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final full = text;
    if (full.isEmpty) return TextSpan(style: base, text: '');

    final children = <TextSpan>[];
    var i = 0;
    while (i < full.length) {
      final attr = i < _attrs.length ? _attrs[i] : const CharStyle();
      var j = i + 1;
      while (j < full.length) {
        final a = j < _attrs.length ? _attrs[j] : const CharStyle();
        if (a != attr) break;
        j++;
      }
      children.add(TextSpan(
        text: full.substring(i, j),
        style: _applyStyle(base, attr),
      ));
      i = j;
    }
    return TextSpan(style: base, children: children);
  }

  static TextStyle _applyStyle(TextStyle base, CharStyle a) {
    var st = base;
    if (a.size != null) {
      st = st.copyWith(fontSize: a.size);
    }
    if (a.bold) {
      st = st.copyWith(fontWeight: FontWeight.w800);
    }
    if (a.italic) {
      st = st.copyWith(fontStyle: FontStyle.italic);
    }
    return st;
  }

  // ---------------------------------------------------------------- yazma

  /// Büyük puntoları masaüstü için başlık etiketlerine eşler.
  static int? _headingForSize(double size) {
    if (size >= 28) return 1;
    if (size >= 21) return 2;
    if (size >= 17.5) return 3;
    return null;
  }

  /// İçeriği masaüstü uyumlu HTML'e çevirir.
  String toHtml() {
    final full = text;
    final buf = StringBuffer();

    // Görseller not içeriğinin başında (ilk kısım).
    for (final img in images) {
      buf.write('<img src="${_escapeAttr(img)}" />');
    }

    var i = 0;
    while (i <= full.length) {
      var j = full.indexOf('\n', i);
      if (j < 0) j = full.length;
      final line = full.substring(i, j);

      if (line.trim().isNotEmpty) {
        final uniform = _lineUniformStyle(i, j);
        final inline = _inlineHtml(i, j);
        final heading = uniform == null ? null : _headingForSize(uniform);
        if (heading != null) {
          buf.write('<h$heading>$inline</h$heading>');
        } else {
          buf.write('<p>$inline</p>');
        }
      }

      if (j >= full.length) break;
      i = j + 1;
    }
    return buf.toString();
  }

  /// Satırdaki boşluk olmayan tüm karakterler aynı puntoya sahipse onu döner.
  double? _lineUniformStyle(int start, int end) {
    double? size;
    var any = false;
    for (var i = start; i < end && i < _attrs.length; i++) {
      if (text[i].trim().isEmpty) continue;
      final s = _attrs[i].effectiveSize;
      if (!any) {
        size = s;
        any = true;
      } else if (size != s) {
        return null;
      }
    }
    return any ? size : null;
  }

  String _inlineHtml(int start, int end) {
    final buf = StringBuffer();
    var i = start;
    while (i < end) {
      final attr = i < _attrs.length ? _attrs[i] : const CharStyle();
      var j = i + 1;
      while (j < end) {
        final a = j < _attrs.length ? _attrs[j] : const CharStyle();
        if (a.bold != attr.bold ||
            a.italic != attr.italic ||
            a.size != attr.size) {
          break;
        }
        j++;
      }
      var seg = _escapeText(text.substring(i, j));

      // Satır başlık olarak yazılmıyorsa özel puntoyu span ile koru.
      final lineUniform = _lineUniformStyle(start, end);
      final isHeading =
          lineUniform != null && _headingForSize(lineUniform) != null;
      if (!isHeading && attr.size != null) {
        seg = '<span style="font-size:${_fmtSize(attr.size!)}px">$seg</span>';
      }
      if (attr.bold && attr.italic) {
        seg = '<b><i>$seg</i></b>';
      } else if (attr.bold) {
        seg = '<b>$seg</b>';
      } else if (attr.italic) {
        seg = '<i>$seg</i>';
      }
      buf.write(seg);
      i = j;
    }
    return buf.toString();
  }
}

String _fmtSize(double size) =>
    size == size.roundToDouble() ? size.toInt().toString() : size.toString();

// =====================================================================
// HTML çözümleme (yükleme) — dosya seviyesinde yardımcılar
// =====================================================================

class _ParsedNote {
  final String text;
  final List<CharStyle> attrs;
  final List<String> images;
  _ParsedNote(this.text, this.attrs, this.images);
}

_ParsedNote _parseNoteHtml(String raw) {
  final looksHtml = RegExp(
    r'<(p|br|div|span|b|strong|i|em|h[1-6]|ul|ol|li|img|font)\b',
    caseSensitive: false,
  ).hasMatch(raw);

  final text = StringBuffer();
  final attrs = <CharStyle>[];
  final images = <String>[];

  void addText(String s, CharStyle st) {
    if (s.isEmpty) return;
    text.write(s);
    for (var k = 0; k < s.length; k++) {
      attrs.add(st);
    }
  }

  if (!looksHtml) {
    addText(raw, const CharStyle());
    return _ParsedNote(_trimEdges(text.toString(), attrs), attrs, images);
  }

  var bold = false;
  var italic = false;
  double? size;

  CharStyle current() => CharStyle(bold: bold, italic: italic, size: size);

  var i = 0;
  while (i < raw.length) {
    final lt = raw.indexOf('<', i);
    if (lt < 0) {
      final tail = _decode(raw.substring(i));
      if (!(tail.trim().isEmpty && tail.contains('\n'))) {
        addText(tail, current());
      }
      break;
    }
    if (lt > i) {
      final chunk = _decode(raw.substring(i, lt));
      if (!(chunk.trim().isEmpty && chunk.contains('\n'))) {
        addText(chunk, current());
      }
    }
    final gt = raw.indexOf('>', lt);
    if (gt < 0) break;
    final tag = raw.substring(lt + 1, gt).trim();
    final lower = tag.toLowerCase();
    final closing = lower.startsWith('/');
    final name =
        lower.replaceFirst(RegExp(r'^/'), '').split(RegExp(r'[\s/]')).first;

    if (name == 'img') {
      final m = RegExp(r'''src=["']([^"']+)["']''').firstMatch(tag);
      if (m != null && m.group(1)!.isNotEmpty) {
        images.add(_decode(m.group(1)!));
      }
    } else if (name == 'br') {
      addText('\n', const CharStyle());
    } else if (name == 'p' || name == 'div' || name == 'font') {
      if (closing && name != 'font') addText('\n', const CharStyle());
    } else if (name == 'li') {
      if (closing) {
        addText('\n', const CharStyle());
      } else {
        if (text.isNotEmpty && !text.toString().endsWith('\n')) {
          addText('\n', const CharStyle());
        }
        addText('• ', const CharStyle());
      }
    } else if (name == 'ul' || name == 'ol') {
      // Liste etiketleri yeni satır üretmez; <li> üretir.
    } else if (name == 'b' || name == 'strong') {
      bold = !closing;
    } else if (name == 'i' || name == 'em') {
      italic = !closing;
    } else if (name == 'span') {
      if (closing) {
        size = null;
      } else {
        final m = RegExp(r'font-size\s*:\s*([\d.]+)').firstMatch(lower);
        size = m == null ? null : double.tryParse(m.group(1)!);
      }
    } else if (RegExp(r'^h[1-6]$').hasMatch(name)) {
      if (closing) {
        size = null;
        addText('\n', const CharStyle());
      } else {
        final lvl = int.parse(name.substring(1));
        size = lvl <= 1
            ? 28
            : lvl == 2
                ? 22
                : 18;
      }
    }
    i = gt + 1;
  }

  final trimmed = _collapseNewlines(_trimEdges(text.toString(), attrs), attrs);
  return _ParsedNote(trimmed, attrs, images);
}

/// En fazla bir boş satıra izin verir (arka arkaya 3+ yeni satır -> 2).
String _collapseNewlines(String s, List<CharStyle> attrs) {
  final out = StringBuffer();
  final rebuilt = <CharStyle>[];
  var i = 0;
  while (i < s.length) {
    if (s[i] == '\n') {
      var j = i;
      while (j < s.length && s[j] == '\n') {
        j++;
      }
      final keep = (j - i) >= 2 ? 2 : 1;
      for (var k = 0; k < keep; k++) {
        out.write('\n');
        rebuilt.add(const CharStyle());
      }
      i = j;
    } else {
      out.write(s[i]);
      rebuilt.add(i < attrs.length ? attrs[i] : const CharStyle());
      i++;
    }
  }
  attrs
    ..clear()
    ..addAll(rebuilt);
  return out.toString();
}

/// Baş/son boşlukları atar ve `attrs`'ı buna göre kırpar.
String _trimEdges(String s, List<CharStyle> attrs) {
  var startIdx = 0;
  while (startIdx < s.length && (s[startIdx] == '\n' || s[startIdx] == ' ')) {
    startIdx++;
  }
  var endIdx = s.length;
  while (endIdx > startIdx && (s[endIdx - 1] == '\n' || s[endIdx - 1] == ' ')) {
    endIdx--;
  }
  if (startIdx == 0 && endIdx == s.length) return s;
  if (endIdx > startIdx) {
    attrs.removeRange(endIdx, attrs.length);
    attrs.removeRange(0, startIdx);
  } else {
    attrs.clear();
  }
  return s.substring(startIdx, endIdx);
}

const Map<String, String> _entities = {
  '&nbsp;': ' ',
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&hellip;': '\u2026',
  '&mdash;': '\u2014',
  '&ndash;': '\u2013',
};

String _decode(String s) {
  var out = s;
  _entities.forEach((k, v) => out = out.replaceAll(k, v));
  return out;
}

String _escapeText(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _escapeAttr(String s) => _escapeText(s).replaceAll('"', '&quot;');
