import 'package:intl/intl.dart';

class DocumentDateRange {
  DocumentDateRange({
    required String text,
    required bool isBirthDate,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    first = DateTime(1900);
    last =
        isBirthDate
            ? DateTime(today.year, today.month, today.day)
            : DateTime(2199, 12, 31);
    DateTime? current;
    try {
      current = DateFormat('dd-MM-yyyy').parseStrict(text.trim());
    } on FormatException {
      // Empty or invalid OCR input must not prevent opening the calendar.
    }
    final candidate = current ?? DateTime(today.year, today.month, today.day);
    initial =
        candidate.isBefore(first)
            ? first
            : candidate.isAfter(last)
            ? last
            : candidate;
  }

  late final DateTime first;
  late final DateTime last;
  late final DateTime initial;
}
