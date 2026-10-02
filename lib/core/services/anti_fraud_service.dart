import 'dart:convert';
import 'package:crypto/crypto.dart';

class VerificationResult {
  final bool isValid;
  final String? failureReason;
  final String? tokenHash;

  VerificationResult({
    required this.isValid,
    this.failureReason,
    this.tokenHash,
  });
}

class AntiFraudService {
  // In-memory set of used token hashes for replay attack prevention
  static final Set<String> _consumedTokenSignatures = {};
  
  // Rate limiting map: userId -> last verification timestamp
  static final Map<String, DateTime> _lastVerificationAttempts = {};

  /// Generates a rotating ephemeral presence token for an active check
  static String generatePresenceToken({
    required String sessionId,
    required String checkId,
    required DateTime timestamp,
    String secret = 'HN_SECURE_TOKEN_SALT_2026',
  }) {
    final payload = '$sessionId:$checkId:${timestamp.millisecondsSinceEpoch}:$secret';
    final bytes = utf8.encode(payload);
    final digest = sha256.convert(bytes);
    // 16-character alphanumeric representation for compact BLE advertising packets
    return digest.toString().substring(0, 16).toUpperCase();
  }

  /// Generates a member response proof when they discover the organizer's active BLE check token
  static String generateMemberProof({
    required String presenceToken,
    required String memberId,
    required DateTime timestamp,
    String? deviceFingerprint,
  }) {
    final payload = '$presenceToken:$memberId:${deviceFingerprint ?? "dev"}:${timestamp.millisecondsSinceEpoch}';
    final bytes = utf8.encode(payload);
    return sha256.convert(bytes).toString();
  }

  /// Verifies member verification attempt against anti-fraud rules
  static VerificationResult verifyProof({
    required String sessionId,
    required String checkId,
    required String memberId,
    required String receivedToken,
    required DateTime checkExpiresAt,
    required DateTime proofTimestamp,
    String? deviceFingerprint,
  }) {
    final now = DateTime.now();

    // 1. Check Token Expiry
    if (now.isAfter(checkExpiresAt.add(const Duration(seconds: 15)))) {
      return VerificationResult(
        isValid: false,
        failureReason: 'Presence check window has expired.',
      );
    }

    // 2. Clock Skew & Future Timestamp Defense
    final skew = proofTimestamp.difference(now).abs();
    if (skew > const Duration(seconds: 45)) {
      return VerificationResult(
        isValid: false,
        failureReason: 'Timestamp discrepancy detected (clock drift > 45s).',
      );
    }

    // 3. Replay Attack Defense
    final uniqueSignature = '$checkId:$memberId:$receivedToken';
    final signatureHash = sha256.convert(utf8.encode(uniqueSignature)).toString();

    if (_consumedTokenSignatures.contains(signatureHash)) {
      return VerificationResult(
        isValid: false,
        failureReason: 'Replay attack prevented: token proof already consumed.',
      );
    }

    // 4. Rate Limiting Protection (Anti-Spam / Anti-Proxy flooding)
    final lastAttempt = _lastVerificationAttempts[memberId];
    if (lastAttempt != null && now.difference(lastAttempt) < const Duration(seconds: 3)) {
      return VerificationResult(
        isValid: false,
        failureReason: 'Too many rapid verification attempts. Please wait.',
      );
    }
    _lastVerificationAttempts[memberId] = now;

    // Mark as consumed
    _consumedTokenSignatures.add(signatureHash);

    return VerificationResult(
      isValid: true,
      tokenHash: signatureHash,
    );
  }

  /// Clean old replay caches periodically
  static void purgeOldSignatures() {
    if (_consumedTokenSignatures.length > 5000) {
      _consumedTokenSignatures.clear();
    }
  }

  /// Reset in-memory rate limiting and consumed signatures for testing
  static void resetForTesting() {
    _consumedTokenSignatures.clear();
    _lastVerificationAttempts.clear();
  }
}
