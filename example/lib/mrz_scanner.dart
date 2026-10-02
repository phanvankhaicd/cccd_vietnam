import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'mrz_parser.dart';
export 'mrz_parser.dart' show MrzData;

class MrzScanner extends StatefulWidget {
  final Function(MrzData) onMrzDetected;

  const MrzScanner({super.key, required this.onMrzDetected});

  @override
  State<MrzScanner> createState() => _MrzScannerState();
}

class _MrzScannerState extends State<MrzScanner> with WidgetsBindingObserver {
  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _picker = ImagePicker();
  final MrzParser _parser = MrzParser();
  final StableMrzResult _stable = StableMrzResult();
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _busy = false;
  bool _delivered = false;
  bool _foreground = true;
  bool _cameraFailed = false;
  bool _closed = false;
  String _scanResult = 'Đang mở camera…';
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _recognitionTask = Future.value();
  Future<void> _cameraTask = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleCamera();
  }

  void _status(String text) {
    if (mounted && !_closed && _scanResult != text) {
      setState(() => _scanResult = text);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _stable.reset();
    _scheduleCamera();
  }

  void _scheduleCamera() {
    _cameraTask = _cameraTask.then((_) => _syncCamera());
  }

  Future<void> _syncCamera() async {
    try {
      if (_closed || !_foreground || _delivered) {
        final old = _cameraController;
        _cameraController = null;
        if (mounted && !_closed) setState(() => _isCameraInitialized = false);
        await old?.dispose();
        return;
      }
      if (_cameraController == null) {
        final cameras = await availableCameras();
        if (_closed || !_foreground) return;
        if (cameras.isEmpty) throw StateError('No camera');
        final camera = cameras.firstWhere(
          (item) => item.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );
        final controller = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup:
              Platform.isAndroid
                  ? ImageFormatGroup.nv21
                  : ImageFormatGroup.bgra8888,
        );
        _cameraController = controller;
        await controller.initialize();
        if (_closed || !_foreground) {
          _cameraController = null;
          await controller.dispose();
          return;
        }
        setState(() {
          _isCameraInitialized = true;
          _cameraFailed = false;
        });
      }
      await _startStream();
    } catch (_) {
      final old = _cameraController;
      _cameraController = null;
      try {
        await old?.dispose();
      } catch (_) {
        /* Already released. */
      }
      if (mounted && !_closed) {
        setState(() {
          _cameraFailed = true;
          _isCameraInitialized = false;
        });
        _status(
          'Không mở được camera. Hãy kiểm tra quyền camera hoặc chọn ảnh.',
        );
      }
    }
  }

  Future<void> _startStream() async {
    final controller = _cameraController;
    if (_closed ||
        !_foreground ||
        _delivered ||
        _isProcessing ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.startImageStream(_onFrame);
      _status('Đang tự nhận diện MRZ… Giữ thẻ ổn định.');
    } catch (_) {
      _status(
        'Không bật được quét tự động. Bạn có thể chụp MRZ hoặc chọn ảnh.',
      );
    }
  }

  InputImage? _inputImage(CameraImage image, CameraController controller) {
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    final expectedFormat =
        Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888;
    if (image.format.group != expectedFormat) return null;
    var rotation = controller.description.sensorOrientation;
    if (Platform.isAndroid) {
      const orientations = {
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };
      final compensation = orientations[controller.value.deviceOrientation]!;
      rotation =
          controller.description.lensDirection == CameraLensDirection.front
              ? (rotation + compensation) % 360
              : (rotation - compensation + 360) % 360;
    }
    final imageRotation = InputImageRotationValue.fromRawValue(rotation);
    if (imageRotation == null) return null;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      inputImageData: InputImageData(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        imageRotation: imageRotation,
        inputImageFormat:
            Platform.isAndroid
                ? InputImageFormat.nv21
                : InputImageFormat.bgra8888,
        planeData: [
          InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            width: image.width,
            height: image.height,
          ),
        ],
      ),
    );
  }

  void _onFrame(CameraImage image) {
    final controller = _cameraController;
    final now = DateTime.now();
    if (_closed ||
        !_foreground ||
        _delivered ||
        _isProcessing ||
        _busy ||
        controller == null ||
        now.difference(_lastFrame).inMilliseconds < 500) {
      return;
    }
    _lastFrame = now;
    final input = _inputImage(image, controller);
    if (input == null) {
      _status('Thiết bị chưa hỗ trợ quét tự động. Hãy chụp MRZ hoặc chọn ảnh.');
      return;
    }
    _busy = true;
    _recognitionTask = _recognizeFrame(input);
  }

  Future<void> _recognizeFrame(InputImage input) async {
    try {
      final text = await _textRecognizer.processImage(input);
      if (_closed || !_foreground || _isProcessing || _delivered) return;
      final data = _parser.parse(text.text, automatic: true);
      final stable = _stable.add(data);
      if (stable != null) {
        await _deliver(stable);
      } else {
        _status(
          data == null
              ? 'Đang tự nhận diện MRZ… Giữ thẻ ổn định.'
              : 'Đã thấy MRZ. Giữ yên để xác nhận…',
        );
      }
    } catch (_) {
      _stable.reset();
      _status('Chưa đọc được khung hình. Giữ thẻ rõ nét hoặc chụp MRZ.');
    } finally {
      _busy = false;
    }
  }

  Future<void> _deliver(MrzData data) async {
    if (_closed || !mounted || _delivered) return;
    _delivered = true;
    final controller = _cameraController;
    if (controller != null && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {
        /* Exiting scanner. */
      }
    }
    if (mounted && !_closed) widget.onMrzDetected(data);
  }

  Future<void> _getImageFromCamera() => _manualScan(fromGallery: false);
  Future<void> _getImageFromGallery() => _manualScan(fromGallery: true);

  Future<void> _manualScan({required bool fromGallery}) async {
    if (_closed || _delivered || _isProcessing) return;
    setState(() => _isProcessing = true);
    _stable.reset();
    File? temporaryPhoto;
    try {
      await _cameraTask;
      final controller = _cameraController;
      if (controller != null && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await _recognitionTask;
      if (_closed) return;
      XFile? photo;
      if (fromGallery) {
        photo = await _picker.pickImage(source: ImageSource.gallery);
      } else {
        if (controller == null || !controller.value.isInitialized) {
          _status('Camera chưa sẵn sàng. Bạn có thể chọn ảnh.');
          return;
        }
        photo = await controller.takePicture();
        temporaryPhoto = File(photo.path);
      }
      if (photo == null || _closed) return;
      _status('Đang nhận diện vùng MRZ…');
      _recognitionTask = _recognizePhoto(File(photo.path)).catchError((
        Object _,
      ) {
        _status('Không đọc được ảnh. Vui lòng thử lại.');
      });
      await _recognitionTask;
    } catch (_) {
      _status('Không đọc được ảnh. Vui lòng thử lại.');
    } finally {
      if (temporaryPhoto != null) {
        try {
          await temporaryPhoto.delete();
        } catch (_) {
          /* Best-effort cleanup. */
        }
      }
      if (mounted && !_closed) {
        setState(() => _isProcessing = false);
        if (!_delivered) _scheduleCamera();
      }
    }
  }

  Future<void> _recognizePhoto(File photo) async {
    final text = await _textRecognizer.processImage(InputImage.fromFile(photo));
    if (_closed || !mounted) return;
    final data = _parser.parse(text.text);
    if (data != null) {
      await _deliver(data);
    } else {
      _status('Chưa thấy MRZ hợp lệ. Đưa đủ 3 dòng mã vào khung hình.');
    }
  }

  Future<void> _closeRecognizer() async {
    try {
      await _recognitionTask;
    } catch (_) {
      /* Error already shown in UI. */
    }
    try {
      await _textRecognizer.close();
    } catch (_) {
      /* Native cleanup. */
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _scheduleCamera();
    unawaited(_closeRecognizer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFB5121B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'QUÉT MÃ MRZ',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/citizen_background.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Đưa 3 dòng mã ở mặt sau thẻ vào đúng khung hình',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF8F1519),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tự quét khi mã rõ nét • Giữ yên, đủ sáng, tránh phản chiếu',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF6D625E), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF221F1F),
                          border: Border.all(color: const Color(0xFFE4C7AE)),
                        ),
                        child:
                            _isCameraInitialized
                                ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CameraPreview(_cameraController!),
                                    CustomPaint(painter: MrzScannerOverlay()),
                                    const Positioned(
                                      left: 20,
                                      right: 20,
                                      bottom: 24,
                                      child: Text(
                                        'TỰ ĐỘNG NHẬN DIỆN • MRZ',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                                : Center(
                                  child:
                                      _cameraFailed
                                          ? TextButton(
                                            onPressed: _scheduleCamera,
                                            child: const Text('THỬ LẠI CAMERA'),
                                          )
                                          : const CircularProgressIndicator(
                                            color: Color(0xFFD71920),
                                          ),
                                ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child:
                        _scanResult.isEmpty
                            ? const SizedBox(height: 20)
                            : Text(
                              _scanResult,
                              key: ValueKey(_scanResult),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF8F1519),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _isProcessing ? null : _getImageFromGallery,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('CHỌN ẢNH'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB5121B),
                            side: const BorderSide(color: Color(0xFFD99B96)),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _getImageFromCamera,
                          icon:
                              _isProcessing
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(Icons.camera_alt_outlined),
                          label: Text(
                            _isProcessing ? 'ĐANG XỬ LÝ...' : 'CHỤP MRZ',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD71920),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for MRZ scanner overlay
class MrzScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;

    // MRZ is a wide, shallow block near the lower part of the document.
    final Rect outerRect = Rect.fromLTWH(0, 0, width, height);
    final Rect scannerRect = Rect.fromLTWH(
      width * 0.07,
      height * 0.57,
      width * 0.86,
      height * 0.25,
    );

    // Define paints
    final Paint backgroundPaint =
        Paint()
          ..color = Colors.black.withValues(alpha: 0.48)
          ..style = PaintingStyle.fill;

    final Paint borderPaint =
        Paint()
          ..color = const Color(0xFFFFD15C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0;

    // Create path for the background with a hole for the scanner area
    final Path backgroundPath =
        Path()
          ..addRect(outerRect)
          ..addRect(scannerRect)
          ..fillType = PathFillType.evenOdd;

    // Draw background with hole
    canvas.drawPath(backgroundPath, backgroundPaint);

    // Draw border around scanner area
    canvas.drawRect(scannerRect, borderPaint);

    // Add corner markers
    final double cornerSize = 20.0;

    // Top left corner
    canvas.drawLine(
      Offset(scannerRect.left, scannerRect.top + cornerSize),
      Offset(scannerRect.left, scannerRect.top),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scannerRect.left, scannerRect.top),
      Offset(scannerRect.left + cornerSize, scannerRect.top),
      borderPaint,
    );

    // Top right corner
    canvas.drawLine(
      Offset(scannerRect.right - cornerSize, scannerRect.top),
      Offset(scannerRect.right, scannerRect.top),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scannerRect.right, scannerRect.top),
      Offset(scannerRect.right, scannerRect.top + cornerSize),
      borderPaint,
    );

    // Bottom left corner
    canvas.drawLine(
      Offset(scannerRect.left, scannerRect.bottom - cornerSize),
      Offset(scannerRect.left, scannerRect.bottom),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scannerRect.left, scannerRect.bottom),
      Offset(scannerRect.left + cornerSize, scannerRect.bottom),
      borderPaint,
    );

    // Bottom right corner
    canvas.drawLine(
      Offset(scannerRect.right - cornerSize, scannerRect.bottom),
      Offset(scannerRect.right, scannerRect.bottom),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scannerRect.right, scannerRect.bottom),
      Offset(scannerRect.right, scannerRect.bottom - cornerSize),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
