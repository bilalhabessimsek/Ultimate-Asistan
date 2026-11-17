import 'package:flutter_test/flutter_test.dart';

import 'package:ultimate_mobile/screens/notes_screen.dart';

void main() {
  group('NoteModel.fromMap', () {
    test('eksik alanlarda varsayılanları doldurur', () {
      final note = NoteModel.fromMap({'id': 123});

      expect(note.id, '123');
      expect(note.title, '');
      expect(note.content, '');
      expect(note.tag, 'genel');
      expect(note.pinned, false);
      expect(note.updatedAt, greaterThan(0));
    });

    test('bigint updated_at değerini int olarak okur', () {
      final note = NoteModel.fromMap({'id': 'a', 'updated_at': 1700000000000});

      expect(note.updatedAt, 1700000000000);
    });

    test('ISO tarih stringini millis değerine çevirir', () {
      final note = NoteModel.fromMap({
        'id': 'a',
        'updated_at': '2024-01-01T00:00:00.000Z',
      });

      expect(
        note.updatedAt,
        DateTime.parse('2024-01-01T00:00:00.000Z').millisecondsSinceEpoch,
      );
    });
  });
}
