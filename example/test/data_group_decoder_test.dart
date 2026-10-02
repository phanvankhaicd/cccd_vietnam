import 'dart:convert';
import 'dart:typed_data';
import 'package:cccd_vietnam/dmrtd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_scan/data_group_decoder.dart';

Uint8List tlv(int tag, List<int> value) =>
    TLV.encode(tag, Uint8List.fromList(value));
void main() {
  test(
    'DG13 decodes nested numbered fields and keeps unknown labels neutral',
    () {
      final data = tlv(
        0x6d,
        tlv(
          0x30,
          tlv(0x31, [
            ...tlv(0x30, [
              ...tlv(2, [2]),
              ...tlv(0x0c, utf8.encode('Nguyễn Văn An')),
            ]),
            ...tlv(0x30, [
              ...tlv(2, [8]),
              ...tlv(0x0c, utf8.encode('Hà Nội')),
            ]),
          ]),
        ),
      );
      final result = decodeDataGroup(data, dg13: true);
      expect(result, contains('Họ và tên: Nguyễn Văn An'));
      expect(result, contains('Trường 8: Hà Nội'));
    },
  );
  test('decodes known text tags and OIDs, leaves keys as binary', () {
    final data = tlv(0x6b, [
      ...tlv(0x5f0e, utf8.encode('NGUYEN<<VAN<AN')),
      ...tlv(6, [42, 134, 72, 134, 247, 13, 1, 1, 1]),
      ...tlv(3, [0, 255, 0, 1]),
    ]);
    final result = decodeDataGroup(data);
    expect(result, contains('NGUYEN  VAN AN'));
    expect(result, contains('1.2.840.113549.1.1.1'));
    expect(result, contains('4 byte — hex: 00ff0001'));
  });
  test('malformed input returns a readable fallback', () {
    expect(
      decodeDataGroup(Uint8List.fromList([0x6d, 20, 1])),
      contains('Không phân tích được'),
    );
  });
  test(
    'DG2 reads unsigned three-byte fields and extracts only image bytes',
    () {
      final data = Uint8List(50);
      data.setRange(0, 8, [0x46, 0x41, 0x43, 0, 0x30, 0x31, 0x30, 0]);
      final view = ByteData.sublistView(data);
      view.setUint32(8, 50);
      view.setUint16(12, 1);
      view.setUint32(14, 36);
      data.setRange(23, 26, [0x80, 0, 1]);
      view.setUint16(36, 300);
      view.setUint16(38, 400);
      data.setRange(46, 50, [255, 216, 255, 217]);
      Uint8List wrap() => tlv(
        0x75,
        tlv(0x7f61, [
          ...tlv(2, [1]),
          ...tlv(0x7f60, [...tlv(0xa1, []), ...tlv(0x5f2e, data)]),
        ]),
      );
      final dg2 = EfDG2.fromBytes(wrap());
      expect(dg2.featureMask, 0x800001);
      expect(dg2.imageWidth, 300);
      expect(dg2.imageHeight, 400);
      expect(dg2.imageData, [255, 216, 255, 217]);
      data[0] = 0;
      expect(() => EfDG2.fromBytes(wrap()), throwsA(isA<EfParseError>()));
      data[0] = 0x46;
      view.setUint32(14, 500);
      expect(() => EfDG2.fromBytes(wrap()), throwsA(isA<EfParseError>()));
    },
  );
}
