import 'package:clinical_assistant/data/session_store.dart';
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

    test('hasResidualStructuralPii detects unsanitized phone', () {
      expect(
        PiiScrubber.hasResidualStructuralPii('Call 9841234567 now'),
        isTrue,
      );
      expect(
        PiiScrubber.hasResidualStructuralPii(
          'ORS ${PiiScrubber.redacted} zinc',
        ),
        isFalse,
      );
    });
  });

  group('reject-to-queue (PI-03)', () {
    test('statusForScrubGate maps residual reject to blocked_residual_pii', () {
      const rejected = SyncScrubResult(
        allowed: false,
        scrubbed: 'ORS [REDACTED]',
        reason: 'Rejected — residual structural PII after scrub',
      );
      expect(
        SessionStore.statusForScrubGate(rejected),
        SessionStore.statusBlockedResidualPii,
      );
      expect(
        SessionStore.statusForScrubGate(rejected),
        isNot(SessionStore.statusPending),
      );
    });

    test('statusForScrubGate maps allowed scrub to pending', () {
      const allowed = SyncScrubResult(
        allowed: true,
        scrubbed: 'ORS [REDACTED] zinc',
        reason: 'Scrubbed — ready for queue (authorized by Terms acceptance)',
      );
      expect(
        SessionStore.statusForScrubGate(allowed),
        SessionStore.statusPending,
      );
    });

    test('listPendingSync filter excludes blocked_residual_pii rows', () {
      // Mirrors SessionStore.listPendingSync web/native WHERE status = pending.
      final queue = [
        {'id': 'sync_ok', 'status': SessionStore.statusPending},
        {
          'id': 'sync_008',
          'status': SessionStore.statusBlockedResidualPii,
          'scrub_note': 'Rejected — residual structural PII after scrub',
        },
        {'id': 'sync_synced', 'status': 'synced'},
      ];
      final pending = queue
          .where((m) => m['status'] == SessionStore.statusPending)
          .toList();
      expect(pending, hasLength(1));
      expect(pending.first['id'], 'sync_ok');
      expect(
        queue.any((m) => m['status'] == 'rejected'),
        isFalse,
        reason: 'Legacy rejected status must not appear; use blocked_residual_pii',
      );
    });
  });
}
