import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/file_io.dart';
import '../utils/rich_note_controller.dart';

/// Not düzenleme ekranı — **gerçek WYSIWYG**.
///
/// Kullanıcı hiçbir "kod"/işaret görmez: yazıyı seçip **Kalın**'a bastığında
/// yazı sadece kalınlaşır (boyutu değişmez), **punto** seçtiğinde yazı
/// Word'deki gibi sayısal olarak büyür/küçülür.
///
/// Görseller galeriden seçilir ve not içeriğinin **başında** gösterilir.
///
/// Kaydederken içerik, masaüstü uygulamasıyla (TipTap/HTML) aynı `notes`
/// tablosunu paylaşabilmek için sessizce HTML'e çevrilir; açılışta HTML
/// tekrar bu zengin modele çözülür.
class NoteDetailScreen extends StatefulWidget {
  final String noteId;
  final String initialTitle;
  final String initialContent;
  final String initialTag;

  const NoteDetailScreen({
    super.key,
    required this.noteId,
    required this.initialTitle,
    required this.initialContent,
    required this.initialTag,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late TextEditingController _titleController;
  late RichNoteController _contentController;
  late TextEditingController _tagController;
  final supabase = Supabase.instance.client;
  final FileIo _fileIo = FileIo();
  bool _isSaving = false;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _contentController = RichNoteController()
      ..loadFromHtml(widget.initialContent);
    _tagController = TextEditingController(text: widget.initialTag);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    setState(() => _isSaving = true);
    try {
      // Veritabanına masaüstü uyumlu HTML olarak yaz (kullanıcı görmez).
      final html = _contentController.toHtml();
      await supabase.from('notes').update({
        'title': _titleController.text.trim(),
        'content': html,
        'tag': _tagController.text.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }).eq('id', widget.noteId);
      _toast('Not kaydedildi.');
    } catch (err) {
      debugPrint('Not kaydedilemedi: $err');
      _toast('Not kaydedilemedi.', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              error ? const Color(0xFF7F1D1D) : const Color(0xFF161B22),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// Galeriden görsel seçip nota ekler (not içeriğinin başında görünür).
  Future<void> _addImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final path = await _fileIo.pickImage();
      if (!mounted) return;
      if (path == null || path.isEmpty) return;
      setState(() => _contentController.images.add(path));
      _toast('Görsel eklendi.');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  /// Word'deki yazı boyutu kutusu gibi punto seçtirir.
  Future<void> _pickFontSize() async {
    final current = _contentController.activeSize;
    final custom = TextEditingController();
    final chosen = await showModalBottomSheet<double?>(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Yazı boyutu',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kNoteFontSizes.map<Widget>((size) {
                    final selected = (current - size).abs() < 0.5;
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, size),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color:
                              selected ? Colors.white : const Color(0xFF22222A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          size.toInt().toString(),
                          style: TextStyle(
                            color: selected ? Colors.black : Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: custom,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Özel punto (örn: 27)',
                          hintStyle: TextStyle(color: Colors.grey),
                          isDense: true,
                        ),
                        onSubmitted: (v) {
                          final n = double.tryParse(v.trim());
                          if (n != null && n >= 6 && n <= 96) {
                            Navigator.pop(context, n);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () {
                        final n = double.tryParse(custom.text.trim());
                        if (n != null && n >= 6 && n <= 96) {
                          Navigator.pop(context, n);
                        }
                      },
                      child: const Text('Uygula'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    custom.dispose();
    if (chosen == null) return;
    _contentController.applyFontSizeToLines(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst Bar (Geri Dön ve Kaydet)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Row(
                      children: [
                        Icon(Icons.arrow_back, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Notlara dön',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _isSaving ? null : _saveNote,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _isSaving ? 'Kaydediliyor...' : 'Kaydet',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // Etiket Girişi
                  TextField(
                    controller: _tagController,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Etiket (örn: iş)',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Başlık Girişi
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Not Başlığı...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Araç Çubuğu (seçili biçimi vurgular)
                  AnimatedBuilder(
                    animation: _contentController,
                    builder: (context, _) {
                      final c = _contentController;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _toolbarButton(
                              Icons.format_bold,
                              tooltip: 'Kalın',
                              selected: c.isBold,
                              onTap: c.toggleBold,
                            ),
                            _toolbarButton(
                              Icons.format_italic,
                              tooltip: 'İtalik',
                              selected: c.isItalic,
                              onTap: c.toggleItalic,
                            ),
                            // Word gibi sayısal punto
                            TextButton.icon(
                              onPressed: _pickFontSize,
                              icon: const Icon(Icons.format_size,
                                  color: Colors.grey, size: 18),
                              label: Text(
                                c.activeSize.toInt().toString(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _toolbarButton(
                              Icons.image_outlined,
                              tooltip: 'Galeriden görsel ekle',
                              selected: false,
                              onTap: _addImage,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Metni seç → Kalın/İtalik ya da punto seç. Kalın yazıyı '
                    'kapatmak boyutu değiştirmez. Görsel galeriden eklenir.',
                    style: TextStyle(
                        color: Colors.grey, fontSize: 11, height: 1.4),
                  ),
                  const SizedBox(height: 16),

                  // İçerik Alanı — WYSIWYG. Görseller de metinle aynı kutunun
                  // içinde, metnin ÜSTÜNDE durur (fotoğraf not içeriğidir).
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Gömülü görseller (içeriğin ilk kısmı)
                        AnimatedBuilder(
                          animation: _contentController,
                          builder: (context, _) {
                            final images = _contentController.images;
                            if (images.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...images.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final src = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: _imagePreview(src),
                                        ),
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: GestureDetector(
                                            onTap: () => setState(() =>
                                                _contentController.images
                                                    .removeAt(index)),
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: const BoxDecoration(
                                                color: Color(0xCC000000),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.close,
                                                  color: Colors.white,
                                                  size: 16),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const Divider(color: Colors.white12, height: 2),
                                const SizedBox(height: 14),
                              ],
                            );
                          },
                        ),

                        // Metin (kod/işaret görünmez)
                        TextField(
                          controller: _contentController,
                          minLines: 10,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: kNoteBaseFontSize,
                            height: 1.6,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Düşüncelerini buraya yaz...',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: InputBorder.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Not içeriğine gömülü bir görseli çizer; dosya yoksa yer tutucu gösterir.
  Widget _imagePreview(String src) {
    final file = File(src);
    if (file.existsSync()) {
      return Image.file(
        file,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imagePlaceholder(),
      );
    }
    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 180,
      width: double.infinity,
      color: const Color(0xFF22222A),
      alignment: Alignment.center,
      child:
          const Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40),
    );
  }

  Widget _toolbarButton(
    IconData icon, {
    required String tooltip,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return IconButton(
      icon: Icon(
        icon,
        color: selected ? Colors.white : Colors.grey,
        size: 20,
      ),
      style: selected
          ? IconButton.styleFrom(backgroundColor: Colors.white24)
          : null,
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}
