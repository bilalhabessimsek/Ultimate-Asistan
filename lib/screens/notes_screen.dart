import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/markdown_lite.dart';
import 'note_detail_screen.dart';

/// Supabase `notes` tablosundaki bir satırı temsil eder.
class NoteModel {
  final String id;
  final String title;
  final String content;
  final String tag;
  final bool pinned;
  final int updatedAt;

  NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.tag,
    required this.pinned,
    required this.updatedAt,
  });

  factory NoteModel.fromMap(Map<String, dynamic> map) {
    return NoteModel(
      id: map['id'].toString(),
      title: (map['title'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      tag: (map['tag'] ?? 'genel').toString(),
      pinned: map['pinned'] ?? false,
      updatedAt: _parseUpdatedAt(map['updated_at']),
    );
  }

  /// Listede göstermek için sadeleştirilmiş içerik önizlemesi.
  String get preview => notePlainText(content);

  /// `updated_at` hem epoch (millis) hem de ISO tarih string'i olabilir.
  static int _parseUpdatedAt(dynamic value) {
    if (value == null) return DateTime.now().millisecondsSinceEpoch;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return DateTime.tryParse(value.toString())?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
  }
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  /// Ekran hazır değilken (ör. soğuk başlangıçta paylaşımdan veya kısayoldan
  /// açılma) gelen "yeni not aç" isteği burada tutulur.
  static bool _pendingQuickNewNote = false;

  /// Ekran kuruluyken "yeni not aç" isteğini işleyen işleyici.
  static void Function()? _quickNewNoteHandler;

  /// Widget, bildirim, paylaşım veya simge kısayolundan "yeni not aç" isteği.
  /// Ekran hazır değilse istek saklanır ve ekran kurulunca uygulanır.
  static void requestQuickNewNote() {
    final handler = _quickNewNoteHandler;
    if (handler != null) {
      handler();
    } else {
      _pendingQuickNewNote = true;
    }
  }

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final supabase = Supabase.instance.client;
  List<NoteModel> _notes = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _searchQuery = '';
  RealtimeChannel? _notesChannel;

  @override
  void initState() {
    super.initState();
    NotesScreen._quickNewNoteHandler = _openQuickNewNote;
    _fetchNotes();
    _setupRealtime();
    // Ekran kurulmadan önce gelmiş bir "yeni not" isteği varsa uygula.
    if (NotesScreen._pendingQuickNewNote) {
      NotesScreen._pendingQuickNewNote = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openQuickNewNote());
    }
  }

  @override
  void dispose() {
    if (NotesScreen._quickNewNoteHandler == _openQuickNewNote) {
      NotesScreen._quickNewNoteHandler = null;
    }
    if (_notesChannel != null) {
      supabase.removeChannel(_notesChannel!);
    }
    super.dispose();
  }

  /// Widget, bildirim, paylaşım veya kısayoldan gelen "yeni not aç" isteği.
  void _openQuickNewNote() {
    if (!mounted) return;
    _createNewNote();
  }

  Future<void> _fetchNotes() async {
    try {
      final response = await supabase
          .from('notes')
          .select()
          .order('pinned', ascending: false)
          .order('updated_at', ascending: false);

      if (mounted) {
        setState(() {
          _notes = (response as List).map((e) => NoteModel.fromMap(e)).toList();
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (err) {
      debugPrint('Notlar çekilemedi: $err');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _setupRealtime() {
    _notesChannel = supabase
        .channel('public:notes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notes',
          callback: (payload) {
            // Değişiklik olduğunda listeyi otomatik tazele
            _fetchNotes();
          },
        )
        .subscribe();
  }

  Future<void> _createNewNote() async {
    // Çakışmayı önlemek için mikrosaniye tabanlı kimlik.
    final newId = DateTime.now().microsecondsSinceEpoch.toString();
    const initialContent = '';
    final newNote = {
      'id': newId,
      'title': 'Yeni Not',
      'content': initialContent,
      'tag': 'genel',
      'pinned': false,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      await supabase.from('notes').insert(newNote);
      await _fetchNotes();

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NoteDetailScreen(
            noteId: newId,
            initialTitle: 'Yeni Not',
            initialContent: initialContent,
            initialTag: 'genel',
          ),
        ),
      );
    } catch (err) {
      debugPrint('Not oluşturulamadı: $err');
      _toast('Not oluşturulamadı. Bağlantını kontrol et.', error: true);
    }
  }

  Future<void> _togglePin(NoteModel note) async {
    try {
      await supabase.from('notes').update({
        'pinned': !note.pinned,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }).eq('id', note.id);
      await _fetchNotes();
      _toast(note.pinned ? 'Sabitleme kaldırıldı.' : 'Not sabitlendi.');
    } catch (err) {
      debugPrint('Not sabitlenemedi: $err');
      _toast('Sabitleme değiştirilemedi.', error: true);
    }
  }

  Future<void> _deleteNote(NoteModel note) async {
    try {
      await supabase.from('notes').delete().eq('id', note.id);
      await _fetchNotes();
      _toast('Not silindi.');
    } catch (err) {
      debugPrint('Not silinemedi: $err');
      _toast('Not silinemedi.', error: true);
    }
  }

  Future<void> _confirmDelete(NoteModel note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Notu sil', style: TextStyle(color: Colors.white)),
        content: Text(
          '"${note.title.isEmpty ? 'İsimsiz Not' : note.title}" kalıcı olarak silinsin mi?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteNote(note);
  }

  void _openNoteActions(NoteModel note) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: Colors.white,
              ),
              title: Text(
                note.pinned ? 'Sabitlemeyi kaldır' : 'Sabitle',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _togglePin(note);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title:
                  const Text('Sil', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(note);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filteredNotes = _notes.where((n) {
      return n.title.toLowerCase().contains(query) ||
          n.tag.toLowerCase().contains(query) ||
          n.preview.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst Başlık ve Yeni Ekle Butonu
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KİŞİSEL ALAN',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Notlarım',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: _createNewNote,
                    child: Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child:
                          const Icon(Icons.add, color: Colors.black, size: 28),
                    ),
                  ),
                ],
              ),
            ),

            // Arama Çubuğu
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search, color: Colors.grey, size: 20),
                    hintText: 'Notlarda ara...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),

            // Notlar Listesi
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchNotes,
                color: Colors.white,
                backgroundColor: const Color(0xFF161B22),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white))
                    : filteredNotes.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filteredNotes.length,
                            itemBuilder: (context, index) {
                              final note = filteredNotes[index];
                              return GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => NoteDetailScreen(
                                      noteId: note.id,
                                      initialTitle: note.title,
                                      initialContent: note.content,
                                      initialTag: note.tag,
                                    ),
                                  ),
                                ),
                                onLongPress: () => _openNoteActions(note),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF161B22),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              note.title.isNotEmpty
                                                  ? note.title
                                                  : 'İsimsiz Not',
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (note.pinned)
                                            const Icon(Icons.push_pin,
                                                color: Colors.white, size: 18)
                                          else
                                            const Icon(Icons.push_pin_outlined,
                                                color: Colors.grey, size: 18),
                                        ],
                                      ),
                                      if (note.preview.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          note.preview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 13,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '#${note.tag}',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(
          _hasError ? Icons.cloud_off : Icons.note_alt_outlined,
          color: Colors.grey,
          size: 48,
        ),
        const SizedBox(height: 16),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _hasError
                  ? 'Notlar yüklenemedi. Aşağı çekerek tekrar dene.'
                  : 'Henüz not bulunmuyor. Sağ üstten ekleyebilirsin.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}
