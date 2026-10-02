/// Helper for validating and normalizing HereNow session join codes and QR links.
class JoinCodeHelper {
  /// Normalizes any variation of join code, manual entry, or QR invite URL into standard format (e.g. 'HN-100249').
  ///
  /// Handles:
  /// - Standard: "HN-100249" -> "HN-100249"
  /// - Lowercase: "hn-100249" -> "HN-100249"
  /// - Whitespace: " HN-100249 " -> "HN-100249"
  /// - Missing hyphen: "HN100249" -> "HN-100249"
  /// - Space separated: "HN 100249" -> "HN-100249"
  /// - Numeric only: "100249" -> "HN-100249"
  /// - QR / Deep links: "https://herenow.app/join/HN-100249" -> "HN-100249"
  /// - QR with query params: "https://herenow.app/join/100249?ref=qr" -> "HN-100249"
  /// - Custom alphanumeric codes: "EVENT-2026" -> "EVENT-2026"
  static String normalize(String rawInput) {
    var code = rawInput.trim();
    if (code.isEmpty) return '';

    // 1. Extract code from URL or deep link if present
    if (code.contains('/join/')) {
      final parts = code.split('/join/');
      if (parts.length > 1) {
        code = parts.last.split('?').first.split('#').first.trim();
      }
    } else if (code.contains('://')) {
      code = code.split('/').last.split('?').first.split('#').first.trim();
    }

    // 2. Remove internal whitespace and uppercase
    code = code.replaceAll(RegExp(r'\s+'), '').toUpperCase();

    // 3. If code is purely 6 digits without prefix (e.g. "100249" -> "HN-100249")
    if (RegExp(r'^\d{6}$').hasMatch(code)) {
      return 'HN-$code';
    }

    // 4. If code is "HN" followed by digits without hyphen (e.g. "HN100249" -> "HN-100249")
    final hnMatch = RegExp(r'^HN(\d{6})$').firstMatch(code);
    if (hnMatch != null) {
      return 'HN-${hnMatch.group(1)}';
    }

    return code;
  }

  /// Validates whether the string conforms to a valid join code format.
  static bool isValid(String rawInput) {
    final normalized = normalize(rawInput);
    if (normalized.isEmpty) return false;
    return RegExp(r'^[A-Z0-9_-]{3,20}$').hasMatch(normalized);
  }
}
