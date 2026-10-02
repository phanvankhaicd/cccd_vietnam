import 'package:flutter_test/flutter_test.dart';
import 'package:test_scan/mrz_parser.dart';

String check(String digits) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    sum += int.parse(digits[i]) * weights[i % 3];
  }
  return '${sum % 10}';
}

String sample({String dob = '980402', String doe = '380402'}) =>
    'IDVNM0123456789017<<<<<<<<<<<<<\n'
    '$dob${check(dob)}M$doe${check(doe)}VNM<<<<<<<<<<<0\n'
    'NGUYEN<<VAN<AN<<<<<<<<<<<<<<<<';
void main() {
  test('automatic MRZ returns full CCCD and both dates with valid checks', () {
    final data = MrzParser().parse(sample(), automatic: true)!;
    expect(data.documentNumber, '012345678901');
    expect(data.dateOfBirth, '02-04-1998');
    expect(data.dateOfExpiry, '02-04-2038');
  });
  test('rejects misread checks, impossible dates and incomplete frames', () {
    expect(
      MrzParser().parse(
        sample().replaceFirst('980402${check('980402')}', '9804029'),
        automatic: true,
      ),
      isNull,
    );
    expect(MrzParser().parse(sample(dob: '980231'), automatic: true), isNull);
    expect(
      MrzParser().parse('IDVNM0123456789017<<<<<<<<<<<<<', automatic: true),
      isNull,
    );
    expect(
      MrzParser().parse('012345678901 980402 380402', automatic: true),
      isNull,
    );
  });
  test(
    'accepts only consecutive identical observations and resets on misses',
    () {
      final stable = StableMrzResult();
      final data = MrzParser().parse(sample(), automatic: true)!;
      expect(stable.add(data), isNull);
      expect(stable.add(null), isNull);
      expect(stable.add(data), isNull);
      expect(stable.add(data), same(data));
      stable.reset();
      expect(stable.add(data), isNull);
      final other = MrzData(
        documentNumber: '012345678902',
        dateOfBirth: data.dateOfBirth,
        dateOfExpiry: data.dateOfExpiry,
      );
      expect(stable.add(other), isNull);
      expect(stable.add(other), same(other));
    },
  );
}
