import 'dart:convert';
import 'dart:typed_data';
import 'package:cccd_vietnam/dmrtd.dart';

const _labels = <int, String>{
  0x5F0E: 'Họ và tên',
  0x5F0F: 'Tên khác',
  0x5F10: 'Số định danh',
  0x5F2B: 'Ngày sinh',
  0x5F11: 'Nơi sinh',
  0x5F42: 'Địa chỉ thường trú',
  0x5F12: 'Điện thoại',
  0x5F13: 'Nghề nghiệp',
  0x5F14: 'Chức danh',
  0x5F15: 'Thông tin bổ sung',
  0x5F16: 'Ảnh chứng minh quốc tịch',
  0x5F17: 'Giấy tờ khác',
  0x5F18: 'Thông tin giám hộ',
  0x5F19: 'Cơ quan cấp',
  0x5F26: 'Ngày cấp',
  0x5F1A: 'Người liên quan',
  0x5F1B: 'Ghi chú',
  0x5F1C: 'Yêu cầu thuế / xuất cảnh',
  0x5F1D: 'Ảnh mặt trước',
  0x5F1E: 'Ảnh mặt sau',
  0x5F55: 'Thời điểm cá thể hóa',
  0x5F56: 'Số hệ thống cá thể hóa',
  0x5F1F: 'MRZ',
  0x5C: 'Danh sách thẻ dữ liệu',
  0x5F2E: 'Dữ liệu sinh trắc học',
  0x7F2E: 'Dữ liệu sinh trắc học',
  0x02: 'Số nguyên',
  0x06: 'Mã định danh OID',
  0x03: 'Chuỗi bit / khóa / chữ ký',
  0x04: 'Dữ liệu nhị phân',
  0x30: 'Nhóm dữ liệu',
  0x31: 'Tập dữ liệu',
};
const _dg13Labels = <int, String>{
  1: 'Số CCCD',
  2: 'Họ và tên',
  3: 'Ngày sinh',
  4: 'Giới tính',
  5: 'Quốc tịch',
  12: 'Ngày hết hạn',
};

String hexBytes(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _value(int tag, Uint8List bytes) {
  if (bytes.isEmpty) return '(trống)';
  if (tag == 0x02 && bytes.length <= 8) {
    var n = BigInt.zero;
    for (final b in bytes) {
      n = (n << 8) | BigInt.from(b);
    }
    if (bytes.first & 0x80 != 0) n -= BigInt.one << (bytes.length * 8);
    return n.toString();
  }
  if (tag == 0x06) {
    final parts = <int>[];
    var n = 0;
    for (final b in bytes) {
      n = (n << 7) | (b & 0x7f);
      if (b & 0x80 == 0) {
        parts.add(n);
        n = 0;
      }
    }
    if (parts.isNotEmpty && bytes.last & 0x80 == 0) {
      final first = parts.removeAt(0);
      final root = first < 40 ? 0 : (first < 80 ? 1 : 2);
      return [root, first - root * 40, ...parts].join('.');
    }
  }
  // Only fields defined as text are interpreted as text. Binary keys and
  // biometric records must not be mistaken for strings by coincidence.
  final textTag =
      (tag >= 0x0c && tag <= 0x1e && tag != 0x10 && tag != 0x11) ||
      (_labels.containsKey(tag) &&
          tag >= 0x5F00 &&
          ![0x5F16, 0x5F1D, 0x5F1E, 0x5F2E].contains(tag));
  if (textTag) {
    try {
      final text = utf8.decode(bytes);
      if (!RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(text)) {
        return text.trim().isEmpty
            ? '(trống)'
            : text.replaceAll('<', ' ').trim();
      }
    } on FormatException {
      /* Show binary metadata below. */
    }
  }
  return '${bytes.length} byte — hex: ${hexBytes(bytes.take(32).toList())}${bytes.length > 32 ? '…' : ''}';
}

/// Decodes BER-TLV/ASN.1 fields without treating binary data as encrypted text.
String decodeDataGroup(Uint8List bytes, {bool dg13 = false}) {
  final lines = <String>[];
  var count = 0;
  void walk(Uint8List data, int depth) {
    if (depth > 16 || count > 400) {
      lines.add('… Cấu trúc còn lại xem trong dữ liệu gốc.');
      return;
    }
    var offset = 0;
    while (offset < data.length && count++ < 400) {
      final remaining = Uint8List.sublistView(data, offset);
      final node = TLV.decode(remaining);
      if (node.encodedLen <= 0) throw const FormatException('Invalid length');
      final tag = node.tag.value;
      final indent = '  ' * depth;
      if (dg13 && tag == 0x30 && node.value.isNotEmpty) {
        final key = TLV.decode(node.value);
        if (key.tag.value == 2 &&
            key.value.length <= 2 &&
            key.encodedLen < node.value.length) {
          final val = TLV.decode(
            Uint8List.sublistView(node.value, key.encodedLen),
          );
          if (key.encodedLen + val.encodedLen == node.value.length) {
            final id = key.value.fold<int>(0, (a, b) => (a << 8) | b);
            lines.add(
              '$indent${_dg13Labels[id] ?? 'Trường $id'}: ${_value(val.tag.value, val.value)}',
            );
            offset += node.encodedLen;
            continue;
          }
        }
      }
      final label =
          _labels[tag] ?? 'Thẻ ${tag.toRadixString(16).toUpperCase()}';
      final constructed = remaining.first & 0x20 != 0;
      if (constructed && tag != 0x7F2E) {
        lines.add('$indent$label (${node.value.length} byte)');
        walk(node.value, depth + 1);
      } else {
        lines.add('$indent$label: ${_value(tag, node.value)}');
      }
      offset += node.encodedLen;
    }
  }

  try {
    walk(bytes, 0);
  } catch (_) {
    lines.add(
      'Không phân tích được phần dữ liệu còn lại. Có thể xem dữ liệu gốc bên dưới.',
    );
  }
  return lines.isEmpty ? 'Không có dữ liệu.' : lines.join('\n');
}
