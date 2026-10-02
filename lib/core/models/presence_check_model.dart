class PresenceCheckModel {
  final String id;
  final String sessionId;
  final String initiatorId;
  final String checkToken;
  final String status; // 'active', 'completed', 'expired'
  final DateTime startedAt;
  final DateTime expiresAt;

  PresenceCheckModel({
    required this.id,
    required this.sessionId,
    required this.initiatorId,
    required this.checkToken,
    this.status = 'active',
    required this.startedAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => status == 'active' && !isExpired;

  factory PresenceCheckModel.fromJson(Map<String, dynamic> json) {
    return PresenceCheckModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      initiatorId: json['initiator_id'] as String,
      checkToken: json['check_token'] as String,
      status: json['status'] as String? ?? 'active',
      startedAt: DateTime.parse(json['started_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'initiator_id': initiatorId,
      'check_token': checkToken,
      'status': status,
      'started_at': startedAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    };
  }
}
