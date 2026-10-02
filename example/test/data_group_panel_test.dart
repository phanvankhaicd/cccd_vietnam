import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_scan/data_group_panel.dart';

void main() {
  const channel = MethodChannel('file_saver');
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  for (final outcome in ['saved', 'cancelled', 'error']) {
    testWidgets('DG2 save handles $outcome and preserves original bytes', (
      tester,
    ) async {
      MethodCall? request;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            request = call;
            if (outcome == 'error')
              throw PlatformException(code: 'write_failed');
            return outcome == 'saved' ? '/selected/photo.j2k' : null;
          });
      final bytes = Uint8List.fromList([255, 79, 255, 81]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DataGroupPanel(
                header: 'EF.DG2',
                text: 'Ảnh chân dung',
                imageBytes: bytes,
                jpeg2000: true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('EF.DG2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu ảnh'));
      await tester.pumpAndSettle();
      expect(request?.method, 'saveAs');
      expect(request?.arguments['bytes'], bytes);
      expect(request?.arguments['fileExtension'], '.j2k');
      expect(
        find.text(
          outcome == 'saved'
              ? 'Đã lưu ảnh DG2.'
              : outcome == 'cancelled'
              ? 'Đã hủy lưu ảnh.'
              : 'Không lưu được ảnh. Vui lòng chọn lại nơi lưu và thử lại.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
