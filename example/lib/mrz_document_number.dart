/// Extracts the full identity number present in a Vietnamese MRZ header.
/// The trailing MRZ check digit, when present, is not part of the number.
String? vietnamMrzDocumentNumber(String line) {
  final match = RegExp(r'^I[A-Z<]VNM([0-9]+)(?:<|$)').firstMatch(line);
  if (match == null) return null;

  var number = match.group(1)!;
  if (number.length == 10 || number.length == 13) {
    number = number.substring(0, number.length - 1);
  }
  if (number.length != 9 && number.length != 12) return null;
  return number;
}

/// Uses the last nine digits of a full CCCD number for BAC only.
String bacDocumentNumber(String input) {
  final number = input.trim();
  return RegExp(r'^[0-9]{12}$').hasMatch(number)
      ? number.substring(number.length - 9)
      : number;
}
