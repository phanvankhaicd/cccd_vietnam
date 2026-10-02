import 'package:expandable/expandable.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data_group_decoder.dart';

class DataGroupPanel extends StatefulWidget {
  const DataGroupPanel({
    super.key,
    required this.header,
    required this.text,
    this.collapsedText = '',
    this.rawBytes,
    this.imageBytes,
    this.jpeg2000 = false,
  });
  final String header;
  final String text;
  final String collapsedText;
  final Uint8List? rawBytes;
  final Uint8List? imageBytes;
  final bool jpeg2000;
  @override
  State<DataGroupPanel> createState() => _DataGroupPanelState();
}

class _DataGroupPanelState extends State<DataGroupPanel> {
  bool _saving = false;
  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _saveImage() async {
    final bytes = widget.imageBytes;
    if (_saving || bytes == null || bytes.isEmpty) return;
    setState(() => _saving = true);
    try {
      final codestream =
          widget.jpeg2000 &&
          bytes.length >= 2 &&
          bytes[0] == 0xff &&
          bytes[1] == 0x4f;
      final extension = widget.jpeg2000 ? (codestream ? 'j2k' : 'jp2') : 'jpg';
      final path = await FileSaver.instance.saveAs(
        name: 'anh_DG2_${DateTime.now().millisecondsSinceEpoch}',
        bytes: bytes,
        fileExtension: extension,
        mimeType: widget.jpeg2000 ? MimeType.custom : MimeType.jpeg,
        customMimeType:
            widget.jpeg2000
                ? (codestream ? 'application/octet-stream' : 'image/jp2')
                : null,
      );
      _message(
        path == null || path.isEmpty ? 'Đã hủy lưu ảnh.' : 'Đã lưu ảnh DG2.',
      );
    } catch (_) {
      _message('Không lưu được ảnh. Vui lòng chọn lại nơi lưu và thử lại.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.imageBytes;
    return ExpandablePanel(
      theme: const ExpandableThemeData(
        headerAlignment: ExpandablePanelHeaderAlignment.center,
        tapBodyToCollapse: false,
        hasIcon: true,
        iconColor: Colors.red,
      ),
      header: Text(widget.header),
      collapsed: Text(
        widget.collapsedText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      expanded: Container(
        padding: const EdgeInsets.all(18),
        color: const Color(0xFFEFEFEF),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (image != null && image.isNotEmpty) ...[
              Image.memory(
                image,
                height: 260,
                fit: BoxFit.contain,
                errorBuilder:
                    (_, error, stack) => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Không thể xem trước định dạng ảnh này trên thiết bị. Bạn vẫn có thể lưu ảnh gốc.',
                      ),
                    ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _saving ? null : _saveImage,
                icon: const Icon(Icons.save_alt),
                label: Text(_saving ? 'Đang lưu…' : 'Lưu ảnh'),
              ),
            ],
            TextButton.icon(
              onPressed:
                  () => Clipboard.setData(ClipboardData(text: widget.text)),
              icon: const Icon(Icons.copy),
              label: const Text('Sao chép thông tin'),
            ),
            SelectableText(widget.text),
            if (widget.rawBytes != null)
              ExpansionTile(
                title: const Text('Dữ liệu gốc (hex)'),
                tilePadding: EdgeInsets.zero,
                children: [
                  TextButton(
                    onPressed:
                        () => Clipboard.setData(
                          ClipboardData(text: hexBytes(widget.rawBytes!)),
                        ),
                    child: const Text('Sao chép dữ liệu gốc'),
                  ),
                  SelectableText(hexBytes(widget.rawBytes!)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
