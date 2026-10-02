class PresenceEventModel {
  final String id;
  final String sessionId;
  final String? userId;
  final String? userName;
  final String eventType;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  PresenceEventModel({
    required this.id,
    required this.sessionId,
    this.userId,
    this.userName,
    required this.eventType,
    DateTime? createdAt,
    this.metadata = const {},
  }) : createdAt = createdAt ?? DateTime.now();

  String get readableMessage {
    final name = userName ?? 'Member';
    switch (eventType) {
      case 'joined':
        return '$name joined the session';
      case 'verified_ble':
        return '$name was verified via BLE discovery';
      case 'manually_confirmed':
        return '$name was manually confirmed by organizer';
      case 'marked_missing':
        return '$name was marked missing';
      case 'marked_away':
        return '$name is possibly away';
      case 'left_session':
        return '$name left the session';
      case 'check_started':
        return 'Organizer started a presence check';
      case 'session_ended':
        return 'Session was completed';
      default:
        return 'Event: $eventType';
    }
  }

  factory PresenceEventModel.fromJson(Map<String, dynamic> json) {
    return PresenceEventModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String?,
      userName: json['user_name'] as String?,
      eventType: json['event_type'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'user_id': userId,
      'event_type': eventType,
      'created_at': createdAt.toIso8601String(),
      'metadata': metadata,
    };
  }
}
