import 'package:clinical_assistant/privacy/pii_scrubber.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PiiScrubber', () {
    test('redacts +977 mobile and email', () {
      const input =
          'Call +977-9801122334 or patient.care@example.com about ORS.';
      final out = PiiScrubber.scrub(input);
      expect(out.contains('+977-9801122334'), isFalse);
      expect(out.contains('patient.care@example.com'), isFalse);
      expect(out.contains('ORS'), isTrue);
      expect(out.contains(PiiScrubber.redacted), isTrue);
    });

    test('redacts NMC and HREG ids', () {
      const input = 'Clinician NMC-2019-12345 booked HREG-2025-4421.';
      final out = PiiScrubber.scrub(input);
      expect(out.contains('NMC-2019-12345'), isFalse);
      expect(out.contains('HREG-2025-4421'), isFalse);
    });

    test('evaluateForSync allows scrubbed clinical text', () {
      const input = 'TB DOTS intensive phase — phone 9841234567';
      final result = PiiScrubber.evaluateForSync(input);
      expect(result.allowed, isTrue);
      expect(result.scrubbed.contains('9841234567'), isFalse);
      expect(result.scrubbed.contains('TB'), isTrue);
    });
  });
}
