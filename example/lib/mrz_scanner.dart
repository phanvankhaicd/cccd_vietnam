import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';

class MrzData {
  final String documentNumber;
  final String dateOfBirth;
  final String dateOfExpiry;

  MrzData({
    required this.documentNumber,
    required this.dateOfBirth,
    required this.dateOfExpiry,
  });

  @override
  String toString() {
    return 'Document Number: $documentNumber, DOB: $dateOfBirth, DOE: $dateOfExpiry';
  }
}

class MrzScanner extends StatefulWidget {
  final Function(MrzData) onMrzDetected;

  const MrzScanner({Key? key, required this.onMrzDetected}) : super(key: key);

  @override
  _MrzScannerState createState() => _MrzScannerState();
}

class _MrzScannerState extends State<MrzScanner> {
  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _picker = ImagePicker();
  File? _image;
  bool _isProcessing = false;
  String _scanResult = '';
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _getImageFromCamera() async {
    try {
      if (!_isCameraInitialized) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Camera not initialized')));
        return;
      }

      final XFile? photo = await _cameraController!.takePicture();
      if (photo != null) {
        setState(() {
          _image = File(photo.path);
          _isProcessing = true;
          _scanResult = 'Processing image...';
        });
        await _processImage(_image!);
      }
    } catch (e) {
      print('Error taking picture: $e');
      setState(() {
        _isProcessing = false;
        _scanResult = 'Error taking picture: $e';
      });
    }
  }

  Future<void> _getImageFromGallery() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _isProcessing = true;
        _scanResult = 'Processing image...';
      });
      await _processImage(_image!);
    }
  }

  Future<void> _processImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    try {
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      // Process the recognized text to extract MRZ data
      final mrzData = _extractMrzData(recognizedText.text);

      setState(() {
        _isProcessing = false;
        if (mrzData != null) {
          _scanResult = 'MRZ detected!\n$mrzData';
          widget.onMrzDetected(mrzData);
        } else {
          _scanResult = 'No valid MRZ found. Please try again.';
        }
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _scanResult = 'Error processing image: $e';
      });
    }
  }

  MrzData? _extractMrzData(String text) {
    print('Recognized text: $text');
    final lines = text.split('\n');

    // Clean up the lines - remove spaces, filter out short lines
    final cleanedLines =
        lines
            .map((line) => line.trim().replaceAll(' ', ''))
            .where((line) => line.length > 20) // MRZ lines are typically long
            .toList();

    print('Cleaned lines: $cleanedLines');

    // Different MRZ formats:
    // TD1 (ID Card): 3 lines of 30 characters
    // TD2 (ID Card/Visa): 2 lines of 36 characters
    // TD3 (Passport): 2 lines of 44 characters

    // First, try to find TD3 format (passport)
    final td3Lines = cleanedLines.where((line) => line.length >= 40).toList();
    if (td3Lines.length >= 2) {
      return _extractTD3Format(td3Lines);
    }

    // Then try TD2 format
    final td2Lines =
        cleanedLines
            .where((line) => line.length >= 36 && line.length < 40)
            .toList();
    if (td2Lines.length >= 2) {
      return _extractTD2Format(td2Lines);
    }

    // Finally, try TD1 format
    final td1Lines =
        cleanedLines
            .where((line) => line.length >= 30 && line.length < 36)
            .toList();
    if (td1Lines.length >= 3) {
      return _extractTD1Format(td1Lines);
    }

    // If no standard format is detected, try a more flexible approach
    return _extractFlexibleFormat(cleanedLines);
  }

  MrzData? _extractTD3Format(List<String> lines) {
    // TD3 format (passport):
    // Line 1: P<ISSUING_COUNTRY<SURNAME<<GIVEN_NAMES
    // Line 2: DOCUMENT_NUMBER<CHECK_DIGIT<NATIONALITY<DOB<CHECK_DIGIT<GENDER<DOE<CHECK_DIGIT<PERSONAL_NUMBER

    if (lines.length < 2) return null;

    // Sort by length in descending order to get the longest lines first
    lines.sort((a, b) => b.length.compareTo(a.length));

    final line1 = lines[0];
    final line2 = lines[1];

    print('Processing TD3 line 1: $line1');
    print('Processing TD3 line 2: $line2');

    // Check first character is 'P' (passport)
    if (!line1.startsWith('P')) {
      print('Not a passport MRZ - does not start with P');
      return null;
    }

    try {
      // Document number is typically positions 0-9 in line 2
      final docNumberMatch = RegExp(r'[A-Z0-9]{5,12}[0-9<]').firstMatch(line2);
      if (docNumberMatch == null) {
        print('Could not extract document number');
        return null;
      }

      var docNumber = docNumberMatch.group(0)?.replaceAll('<', '') ?? '';
      print('Raw extracted document number: $docNumber');

      // Clean the document number - remove country code prefixes (like "VN")
      // and extract the numeric part
      final numericMatch = RegExp(r'[0-9]{6,9}').firstMatch(docNumber);
      if (numericMatch != null) {
        docNumber = numericMatch.group(0) ?? docNumber;
        print('Cleaned document number: $docNumber');
      }

      // In line 2, DOB is positions 13-19 (YYMMDD)
      final dobMatch = RegExp(r'[0-9]{6}').allMatches(line2).toList();
      if (dobMatch.isEmpty) {
        print('Could not extract DOB');
        return null;
      }

      // DOE is positions 21-27 (YYMMDD)
      // It's typically the second 6-digit number in the second line
      String? dobString;
      String? doeString;

      if (dobMatch.length >= 2) {
        dobString = dobMatch[0].group(0);
        doeString = dobMatch[1].group(0);
      } else if (dobMatch.length == 1) {
        // If we only found one date, assume it's the DOB and try harder to find DOE
        dobString = dobMatch[0].group(0);

        // Look for another date-like pattern
        final additionalMatch = RegExp(
          r'(?<=[<0-9])[0-9]{6}[0-9<]',
        ).firstMatch(line2);
        if (additionalMatch != null) {
          doeString = additionalMatch.group(0)?.substring(0, 6);
        }
      }

      if (dobString == null || doeString == null) {
        print('Could not extract both dates');
        return null;
      }

      print('Extracted DOB: $dobString, DOE: $doeString');

      // Convert YYMMDD to MM/DD/YYYY format
      final dob = _formatDate(dobString);
      final doe = _formatDate(doeString);

      if (dob == null || doe == null) {
        print('Could not parse dates');
        return null;
      }

      return MrzData(
        documentNumber: docNumber,
        dateOfBirth: dob,
        dateOfExpiry: doe,
      );
    } catch (e) {
      print('Error parsing TD3 format: $e');
      return null;
    }
  }

  MrzData? _extractTD2Format(List<String> lines) {
    // TD2 format (ID card/visa):
    // Line 1: I<ISSUING_COUNTRY<SURNAME<<GIVEN_NAMES
    // Line 2: DOCUMENT_NUMBER<CHECK_DIGIT<NATIONALITY<DOB<CHECK_DIGIT<GENDER<DOE<CHECK_DIGIT<OPTIONAL_DATA

    // Similar to TD3, with different field positions
    if (lines.length < 2) return null;

    lines.sort((a, b) => b.length.compareTo(a.length));

    final line1 = lines[0];
    final line2 = lines[1];

    print('Processing TD2 line 1: $line1');
    print('Processing TD2 line 2: $line2');

    try {
      // Document number in TD2 is typically positions 0-9 in line 2
      final docNumberMatch = RegExp(r'[A-Z0-9]{5,12}[0-9<]').firstMatch(line2);
      if (docNumberMatch == null) return null;

      var docNumber = docNumberMatch.group(0)?.replaceAll('<', '') ?? '';
      print('Raw extracted document number (TD2): $docNumber');

      // Clean the document number - extract just the numeric part
      final numericMatch = RegExp(r'[0-9]{6,9}').firstMatch(docNumber);
      if (numericMatch != null) {
        docNumber = numericMatch.group(0) ?? docNumber;
        print('Cleaned document number (TD2): $docNumber');
      }

      // Extract dates (similar to TD3)
      final dateMatches = RegExp(r'[0-9]{6}').allMatches(line2).toList();
      if (dateMatches.length < 2) return null;

      final dobString = dateMatches[0].group(0);
      final doeString = dateMatches[1].group(0);

      if (dobString == null || doeString == null) return null;

      final dob = _formatDate(dobString);
      final doe = _formatDate(doeString);

      if (dob == null || doe == null) return null;

      return MrzData(
        documentNumber: docNumber,
        dateOfBirth: dob,
        dateOfExpiry: doe,
      );
    } catch (e) {
      print('Error parsing TD2 format: $e');
      return null;
    }
  }

  MrzData? _extractTD1Format(List<String> lines) {
    // TD1 format (ID card):
    // Line 1: I<ISSUING_COUNTRY<DOCUMENT_NUMBER<CHECK_DIGIT
    // Line 2: DOB<CHECK_DIGIT<GENDER<DOE<CHECK_DIGIT<NATIONALITY<OPTIONAL_DATA
    // Line 3: SURNAME<<GIVEN_NAMES

    if (lines.length < 3) return null;

    lines.sort((a, b) => a.length.compareTo(b.length));

    final line1 = lines[0];
    final line2 = lines[1];

    print('Processing TD1 line 1: $line1');
    print('Processing TD1 line 2: $line2');

    try {
      // Document number is in line 1, typically after country code
      final docNumberMatch = RegExp(
        r'(?<=[A-Z<]{3})[A-Z0-9]{5,12}[0-9<]',
      ).firstMatch(line1);
      if (docNumberMatch == null) {
        // Try alternative pattern
        final altMatch = RegExp(r'[A-Z0-9]{5,12}[0-9<]').firstMatch(line1);
        if (altMatch == null) return null;

        var docNumber = altMatch.group(0)?.replaceAll('<', '') ?? '';
        print('Raw extracted document number (TD1 alt): $docNumber');

        // Clean the document number - extract just the numeric part
        final numericMatch = RegExp(r'[0-9]{6,9}').firstMatch(docNumber);
        if (numericMatch != null) {
          docNumber = numericMatch.group(0) ?? docNumber;
          print('Cleaned document number (TD1 alt): $docNumber');
        }

        // In TD1, DOB and DOE are in line 2
        final dateMatches = RegExp(r'[0-9]{6}').allMatches(line2).toList();
        if (dateMatches.length < 2) return null;

        final dobString = dateMatches[0].group(0);
        final doeString = dateMatches[1].group(0);

        if (dobString == null || doeString == null) return null;

        final dob = _formatDate(dobString);
        final doe = _formatDate(doeString);

        if (dob == null || doe == null) return null;

        return MrzData(
          documentNumber: docNumber,
          dateOfBirth: dob,
          dateOfExpiry: doe,
        );
      } else {
        var docNumber = docNumberMatch.group(0)?.replaceAll('<', '') ?? '';
        print('Raw extracted document number (TD1): $docNumber');

        // Clean the document number - extract just the numeric part
        final numericMatch = RegExp(r'[0-9]{6,9}').firstMatch(docNumber);
        if (numericMatch != null) {
          docNumber = numericMatch.group(0) ?? docNumber;
          print('Cleaned document number (TD1): $docNumber');
        }

        // In TD1, DOB and DOE are in line 2
        final dateMatches = RegExp(r'[0-9]{6}').allMatches(line2).toList();
        if (dateMatches.length < 2) return null;

        final dobString = dateMatches[0].group(0);
        final doeString = dateMatches[1].group(0);

        if (dobString == null || doeString == null) return null;

        final dob = _formatDate(dobString);
        final doe = _formatDate(doeString);

        if (dob == null || doe == null) return null;

        return MrzData(
          documentNumber: docNumber,
          dateOfBirth: dob,
          dateOfExpiry: doe,
        );
      }
    } catch (e) {
      print('Error parsing TD1 format: $e');
      return null;
    }
  }

  MrzData? _extractFlexibleFormat(List<String> lines) {
    // Fallback method when standard formats aren't detected

    print('Using flexible format extraction');

    String? docNumber;
    List<String> dates = [];

    for (final line in lines) {
      // Look for document number (usually 9-10 alphanumeric characters)
      if (docNumber == null) {
        // First try to find just numeric part that matches your pattern
        final numericMatch = RegExp(r'[0-9]{6,9}').allMatches(line).toList();
        for (final match in numericMatch) {
          final candidate = match.group(0);
          if (candidate != null) {
            docNumber = candidate;
            print('Found numeric document number: $docNumber');
            break;
          }
        }

        // If no numeric-only match found, look for alphanumeric
        if (docNumber == null) {
          final docMatch = RegExp(r'[A-Z0-9]{6,12}').allMatches(line).toList();
          for (final match in docMatch) {
            final candidate = match.group(0);
            if (candidate != null &&
                (candidate.length >= 6 && candidate.length <= 12) &&
                !RegExp(r'^[0-9]{6}$').hasMatch(candidate)) {
              // Avoid matching dates

              // Try to extract just the numeric part
              final numericPart = RegExp(r'[0-9]{6,9}').firstMatch(candidate);
              if (numericPart != null) {
                docNumber = numericPart.group(0);
                print('Extracted numeric part from alphanumeric: $docNumber');
              } else {
                docNumber = candidate;
                print('Using alphanumeric document number: $docNumber');
              }
              break;
            }
          }
        }
      }

      // Look for dates in YYMMDD format
      final dateMatches = RegExp(r'[0-9]{6}').allMatches(line).toList();
      for (final match in dateMatches) {
        final date = match.group(0);
        if (date != null && !dates.contains(date)) {
          dates.add(date);
        }
      }
    }

    if (docNumber != null && dates.length >= 2) {
      final dob = _formatDate(dates[0]);
      final doe = _formatDate(dates[1]);

      if (dob != null && doe != null) {
        return MrzData(
          documentNumber: docNumber,
          dateOfBirth: dob,
          dateOfExpiry: doe,
        );
      }
    }

    return null;
  }

  String? _formatDate(String yymmdd) {
    try {
      final year = int.parse(yymmdd.substring(0, 2));
      final month = int.parse(yymmdd.substring(2, 4));
      final day = int.parse(yymmdd.substring(4, 6));

      // Validate date parts
      if (month < 1 || month > 12 || day < 1 || day > 31) {
        return null;
      }

      // Adjust years (assuming 20YY for most modern documents)
      final fullYear = year > 50 ? 1900 + year : 2000 + year;

      return '$month/$day/$fullYear';
    } catch (e) {
      print('Error formatting date: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MRZ Scanner')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child:
                _isCameraInitialized
                    ? Stack(
                      children: [
                        CameraPreview(_cameraController!),
                        // Overlay with guidance
                        Positioned.fill(
                          child: CustomPaint(painter: MrzScannerOverlay()),
                        ),
                        // Instruction text
                        Positioned(
                          top: 20,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            color: Colors.black54,
                            child: const Text(
                              'Position the MRZ (machine readable zone) within the frame',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                    : const Center(child: CircularProgressIndicator()),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  _scanResult,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _getImageFromCamera,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Capture'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _getImageFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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

    // Define scanner area (bottom third of screen)
    final Rect outerRect = Rect.fromLTWH(0, 0, width, height);
    final Rect scannerRect = Rect.fromLTWH(
      width * 0.1,
      height * 0.65,
      width * 0.8,
      height * 0.2,
    );

    // Define paints
    final Paint backgroundPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.5)
          ..style = PaintingStyle.fill;

    final Paint borderPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

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
