import 'package:flutter_test/flutter_test.dart';
import 'package:test_scan/document_date_picker.dart';

void main() {
  final now = DateTime(2026, 10, 2);
  test('allows past expiry and expiry more than ten years away', () {
    for (final year in [2025, 2038, 2099]) {
      final range = DocumentDateRange(
        text: '02-04-$year',
        isBirthDate: false,
        now: now,
      );
      expect(range.initial, DateTime(year, 4, 2));
      expect(range.initial.isBefore(range.first), isFalse);
      expect(range.initial.isAfter(range.last), isFalse);
    }
  });
  test('empty or invalid OCR dates still open on a valid date', () {
    for (final text in ['', '31-02-2038', 'invalid']) {
      final range = DocumentDateRange(text: text, isBirthDate: false, now: now);
      expect(range.initial, now);
    }
  });
  test('clamps dates outside the supported calendar range', () {
    expect(
      DocumentDateRange(
        text: '01-01-1800',
        isBirthDate: false,
        now: now,
      ).initial,
      DateTime(1900),
    );
    expect(
      DocumentDateRange(
        text: '01-01-2300',
        isBirthDate: false,
        now: now,
      ).initial,
      DateTime(2199, 12, 31),
    );
    expect(
      DocumentDateRange(
        text: '01-01-2038',
        isBirthDate: true,
        now: now,
      ).initial,
      now,
    );
  });
}
