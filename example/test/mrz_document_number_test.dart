import 'package:flutter_test/flutter_test.dart';
import 'package:test_scan/mrz_document_number.dart';

void main() {
  test('preserves the full number without including the check digit', () {
    expect(vietnamMrzDocumentNumber('IDVNM0123456789017<<<<'), '012345678901');
    expect(vietnamMrzDocumentNumber('IDVNM012345678901<<<<'), '012345678901');
  });

  test('preserves leading zeros and an existing nine-digit number', () {
    expect(vietnamMrzDocumentNumber('IDVNM0120006789017<<<<'), '012000678901');
    expect(vietnamMrzDocumentNumber('IDVNM0006789017<<<<'), '000678901');
    expect(vietnamMrzDocumentNumber('IDVNM000678901<<<<'), '000678901');
  });

  test('rejects incomplete numbers and non-Vietnamese headers', () {
    expect(vietnamMrzDocumentNumber('IDVNM12345678<<<<'), isNull);
    expect(vietnamMrzDocumentNumber('IDVNM01234567890<<<<'), isNull);
    expect(vietnamMrzDocumentNumber('P<VNM0123456789017<<<<'), isNull);
  });

  test('BAC uses the last nine digits for scanned or manually entered CCCD', () {
    final scanned = vietnamMrzDocumentNumber('IDVNM0120006789017<<<<')!;
    expect(scanned, '012000678901');
    expect(bacDocumentNumber(scanned), '000678901');
    expect(bacDocumentNumber(' 012000678901 '), '000678901');
    expect(bacDocumentNumber('000678901'), '000678901');
    expect(bacDocumentNumber('B12345678'), 'B12345678');
  });
}
