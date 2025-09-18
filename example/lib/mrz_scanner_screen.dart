import 'package:flutter/material.dart';
import 'mrz_scanner.dart';

class MrzScannerScreen extends StatelessWidget {
  final Function(String, String, String) onMrzDataReceived;

  const MrzScannerScreen({Key? key, required this.onMrzDataReceived})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MrzScanner(
      onMrzDetected: (MrzData mrzData) {
        // Pass the MRZ data back to the main screen
        onMrzDataReceived(
          mrzData.documentNumber,
          mrzData.dateOfBirth,
          mrzData.dateOfExpiry,
        );

        // Return to the previous screen
        Navigator.pop(context);
      },
    );
  }
}
