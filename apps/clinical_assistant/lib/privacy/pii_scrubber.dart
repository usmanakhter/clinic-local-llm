/// Regex PII scrubber mirrored from `qa/run_fixture_evals.py`.
///
/// Intentional limits: ~30% recall on name/place fixtures; phones, emails,
/// and structural IDs are the primary demo targets. ONNX NER is deferred.
class PiiScrubber {
  PiiScrubber._();

  static const redacted = '[REDACTED]';

  static final List<RegExp> patterns = [
    RegExp(r'\+977[\s\-]?\d{8,10}\b'),
    RegExp(r'(?:\+?977[\s\-]*)?(?:98|97)\d{8}\b'),
    RegExp(r'[९८][०-९]{9}'),
    RegExp(r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b'),
    RegExp(r'\bNMC[\-\s]?\d{4}[\-\s]?\d{4,}\b', caseSensitive: false),
    RegExp(r'\b[A-Z]\d{7}\b'),
    RegExp(r'\bHREG[\-\s]?\d{4}[\-\s]?\d{3,}\b', caseSensitive: false),
    RegExp(r'\bHP[\-\s]?\d{4}[\-\s]?\d{4,}\b', caseSensitive: false),
    RegExp(r'\bNP[\-\s]?[A-Z]{2,4}[\-\s]?\d{9,}\b', caseSensitive: false),
    RegExp(r'\b\d{2,4}/\d{2,4}[\-\s]?\d{6,}\b'),
    RegExp(r'[०-९]{2,4}/[०-९]{2,4}[\-\s]?[०-९]{6,}'),
    RegExp(r'[०-९]{2}[\-\s][०-९]{2}[\-\s][०-९]{2}[\-\s][०-९]{6,}'),
  ];

  /// Replace matched PII spans with [redacted]. Does not invent clinical content.
  static String scrub(String text) {
    var out = text;
    for (final pattern in patterns) {
      out = out.replaceAll(pattern, redacted);
    }
    return out;
  }

  /// True when scrubbing changed the input (or residual phone/email still present).
  static bool hasResidualStructuralPii(String text) {
    for (final pattern in patterns) {
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }

  /// Local sync-queue gate: reject payloads that still contain scrubbable IDs.
  static SyncScrubResult evaluateForSync(String payload) {
    final scrubbed = scrub(payload);
    if (hasResidualStructuralPii(scrubbed)) {
      return SyncScrubResult(
        allowed: false,
        scrubbed: scrubbed,
        reason: 'Rejected — residual structural PII after scrub',
      );
    }
    if (scrubbed != payload) {
      return SyncScrubResult(
        allowed: true,
        scrubbed: scrubbed,
        reason: 'Scrubbed — ready for queue (authorized by Terms acceptance)',
      );
    }
    return SyncScrubResult(
      allowed: true,
      scrubbed: scrubbed,
      reason: 'No structural PII detected',
    );
  }
}

class SyncScrubResult {
  const SyncScrubResult({
    required this.allowed,
    required this.scrubbed,
    required this.reason,
  });

  final bool allowed;
  final String scrubbed;
  final String reason;
}
