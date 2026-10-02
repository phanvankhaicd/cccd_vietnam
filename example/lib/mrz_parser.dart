import 'mrz_document_number.dart';

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

class MrzParser {
  bool _validDateCheck(String digits, String check) {
    const weights = [7, 3, 1];
    var sum = 0;
    for (var i = 0; i < digits.length; i++) {
      sum += int.parse(digits[i]) * weights[i % 3];
    }
    return check == (sum % 10).toString();
  }

  MrzData? parse(String text, {bool automatic = false}) {
    final lines = text.split('\n');

    // Clean up the lines - remove spaces, filter out short lines
    final cleanedLines =
        lines
            .map((line) => line.toUpperCase().replaceAll(RegExp(r'\s+'), ''))
            .where((line) => line.length > 20) // MRZ lines are typically long
            .toList();

    // Handle Vietnamese identity cards before the generic parsers truncate
    // numeric fields. Keep OCR line order and exclude date check digits.
    final vietnamHeader = cleanedLines.indexWhere(
      (line) => RegExp(r'^I[A-Z<]VNM').hasMatch(line),
    );
    if (vietnamHeader >= 0) {
      if (vietnamHeader + 1 >= cleanedLines.length) return null;
      final number = vietnamMrzDocumentNumber(cleanedLines[vietnamHeader]);
      final dates = RegExp(
        r'^([0-9]{6})([0-9<])[MF<]([0-9]{6})([0-9<])',
      ).firstMatch(cleanedLines[vietnamHeader + 1]);
      if (number == null || dates == null) return null;
      if (automatic &&
          (!_validDateCheck(dates.group(1)!, dates.group(2)!) ||
              !_validDateCheck(dates.group(3)!, dates.group(4)!))) {
        return null;
      }
      final dob = _formatDate(dates.group(1)!);
      final doe = _formatDate(dates.group(3)!);
      if (dob == null || doe == null) return null;
      return MrzData(
        documentNumber: number,
        dateOfBirth: dob,
        dateOfExpiry: doe,
      );
    }

    // Automatic acceptance is restricted to the Vietnamese card layout.
    // Manual capture still supports the existing generic document parsers.
    if (automatic) return null;

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

    // Check first character is 'P' (passport)
    if (!line1.startsWith('P')) {
      return null;
    }

    try {
      // Document number is typically positions 0-9 in line 2
      final docNumberMatch = RegExp(r'[A-Z0-9]{5,12}[0-9<]').firstMatch(line2);
      if (docNumberMatch == null) {
        return null;
      }

      var docNumber = docNumberMatch.group(0)?.replaceAll('<', '') ?? '';

      // Clean the document number - remove country code prefixes (like "VN")
      // and extract the numeric part
      final numericMatch = RegExp(r'[0-9]{6,9}').firstMatch(docNumber);
      if (numericMatch != null) {
        docNumber = numericMatch.group(0) ?? docNumber;
      }

      // In line 2, DOB is positions 13-19 (YYMMDD)
      final dobMatch = RegExp(r'[0-9]{6}').allMatches(line2).toList();
      if (dobMatch.isEmpty) {
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
        return null;
      }

      // Convert YYMMDD to dd-MM-yyyy format.
      final dob = _formatDate(dobString);
      final doe = _formatDate(doeString);

      if (dob == null || doe == null) {
        return null;
      }

      return MrzData(
        documentNumber: docNumber,
        dateOfBirth: dob,
        dateOfExpiry: doe,
      );
    } catch (e) {
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

    final line2 = lines[1];

    try {
      // Document number in TD2 is typically positions 0-9 in line 2
      final docNumberMatch = RegExp(r'[A-Z0-9]{5,12}[0-9<]').firstMatch(line2);
      if (docNumberMatch == null) return null;

      var docNumber = docNumberMatch.group(0)?.replaceAll('<', '') ?? '';

      // Clean the document number - extract just the numeric part
      final numericMatch = RegExp(r'[0-9]{6,9}').firstMatch(docNumber);
      if (numericMatch != null) {
        docNumber = numericMatch.group(0) ?? docNumber;
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

        // Clean the document number - extract just the numeric part
        final numericMatch = RegExp(r'[0-9]{6,9}').firstMatch(docNumber);
        if (numericMatch != null) {
          docNumber = numericMatch.group(0) ?? docNumber;
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

        // Clean the document number - extract just the numeric part
        final numericMatch = RegExp(r'[0-9]{6,9}').firstMatch(docNumber);
        if (numericMatch != null) {
          docNumber = numericMatch.group(0) ?? docNumber;
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
      return null;
    }
  }

  MrzData? _extractFlexibleFormat(List<String> lines) {
    // Fallback method when standard formats aren't detected

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
              } else {
                docNumber = candidate;
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

      final parsed = DateTime(fullYear, month, day);
      if (parsed.month != month || parsed.day != day) return null;
      final formattedDay = day.toString().padLeft(2, '0');
      final formattedMonth = month.toString().padLeft(2, '0');
      return '$formattedDay-$formattedMonth-$fullYear';
    } catch (e) {
      return null;
    }
  }
}

/// Requires two consecutive matching observations before accepting a scan.
class StableMrzResult {
  String? _previous;
  int _matches = 0;
  MrzData? add(MrzData? data) {
    if (data == null) {
      reset();
      return null;
    }
    final key =
        '${data.documentNumber}|${data.dateOfBirth}|${data.dateOfExpiry}';
    _matches = key == _previous ? _matches + 1 : 1;
    _previous = key;
    return _matches >= 2 ? data : null;
  }

  void reset() {
    _previous = null;
    _matches = 0;
  }
}
