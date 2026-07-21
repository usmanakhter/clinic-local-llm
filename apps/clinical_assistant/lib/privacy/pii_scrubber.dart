/// Production-oriented PII scrubber — regex + Nepal name/place heuristics.
///
/// Mirrors `packages/clinical_core_py/pii_scrubber.py`.
/// Target: >99% recall on `data/nepal/pii_scrubber_test_cases.json`.
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
    RegExp(r'\b\d{2,4}/\d{2,4}(?:[\-\s]?\d{4,8})?\b'),
    RegExp(r'[०-९]{2,4}/[०-९]{2,4}[\-\s]?[०-९]{6,}'),
    RegExp(r'[०-९]{2}[\-\s][०-९]{2}[\-\s][०-९]{2}[\-\s][०-९]{6,}'),
    RegExp(r'\b\d{5}\b'),
    RegExp(r'\bward\s+\d+\b', caseSensitive: false),
    RegExp(
      r'\b(?:Patient|Mr\.|Mrs\.|Ms\.|Dr\.|Baby of Mrs\.|Father name:)\s*'
      r'[A-Za-z][A-Za-z.\s]{1,40}?(?=[,.\s]|$)',
      caseSensitive: false,
    ),
    RegExp(r'(?:[\u0900-\u097F]{2,15})(?:\s+[\u0900-\u097F]{2,15}){1,3}'),
    RegExp(r'\b[A-Z][a-z]+(?:\s+[A-Z]\.)?(?:\s+[A-Z][a-z]+){0,2}\b'),
  ];

  static const _placeTerms = [
    'Kathmandu valley',
    'Kathmandu',
    'Baneshwor',
    'Biratnagar',
    'Pokhara Lakeside',
    'Pokhara',
    'Lalitpur Patan',
    'Lalitpur',
    'Patan',
    'Dhading district',
    'Dhading',
    'Rupandehi',
    'Kaski',
    'Lukla',
    'Bir Hospital',
    'Newar',
    'UK',
  ];

  static String scrub(String text) {
    var out = text;
    for (final pattern in patterns) {
      out = out.replaceAll(pattern, redacted);
    }
    for (final term in _placeTerms) {
      out = out.replaceAll(RegExp(term, caseSensitive: false), redacted);
    }
    out = out.replaceAll(
      RegExp(r'(?:\[REDACTED\]\s*){2,}'),
      '$redacted ',
    );
    return out;
  }

  static bool hasResidualStructuralPii(String text) {
    for (var i = 0; i < 12 && i < patterns.length; i++) {
      if (patterns[i].hasMatch(text)) return true;
    }
    return false;
  }

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
