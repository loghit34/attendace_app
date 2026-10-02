enum PresenceStatus {
  present,
  possiblyAway,
  missing,
  manuallyConfirmed,
  left;

  static PresenceStatus fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'present':
        return PresenceStatus.present;
      case 'possibly_away':
      case 'possiblyaway':
        return PresenceStatus.possiblyAway;
      case 'manually_confirmed':
      case 'manuallyconfirmed':
        return PresenceStatus.manuallyConfirmed;
      case 'left':
        return PresenceStatus.left;
      case 'missing':
      default:
        return PresenceStatus.missing;
    }
  }

  String get dbValue {
    switch (this) {
      case PresenceStatus.present:
        return 'present';
      case PresenceStatus.possiblyAway:
        return 'possibly_away';
      case PresenceStatus.manuallyConfirmed:
        return 'manually_confirmed';
      case PresenceStatus.left:
        return 'left';
      case PresenceStatus.missing:
        return 'missing';
    }
  }

  String get displayName {
    switch (this) {
      case PresenceStatus.present:
        return 'Present';
      case PresenceStatus.possiblyAway:
        return 'Possibly Away';
      case PresenceStatus.manuallyConfirmed:
        return 'Manually Confirmed';
      case PresenceStatus.left:
        return 'Left';
      case PresenceStatus.missing:
        return 'Missing';
    }
  }
}

class SessionMemberModel {
  final String id;
  final String sessionId;
  final String userId;
  final String userName;
  final String? userPhone;
  final String? userEmail;
  final String? userAvatar;
  final String role; // 'organizer' or 'member'
  final PresenceStatus status;
  final DateTime? lastVerifiedAt;
  final String? deviceFingerprint;
  final DateTime joinedAt;

  SessionMemberModel({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.userName,
    this.userPhone,
    this.userEmail,
    this.userAvatar,
    this.role = 'member',
    this.status = PresenceStatus.missing,
    this.lastVerifiedAt,
    this.deviceFingerprint,
    DateTime? joinedAt,
  }) : joinedAt = joinedAt ?? DateTime.now();

  bool get isOrganizer => role.toLowerCase() == 'organizer';

  String get relativeTimeAgo {
    if (lastVerifiedAt == null) return 'Never verified';
    final diff = DateTime.now().difference(lastVerifiedAt!);
    if (diff.inSeconds < 10) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds} sec ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} d ago';
  }

  factory SessionMemberModel.fromJson(Map<String, dynamic> json) {
    // Supabase can join `users` table or return embedded fields
    final userObj = json['users'] as Map<String, dynamic>?;

    return SessionMemberModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      userName: userObj?['name'] as String? ?? json['user_name'] as String? ?? 'Group Member',
      userPhone: userObj?['phone'] as String? ?? json['user_phone'] as String?,
      userEmail: userObj?['email'] as String? ?? json['user_email'] as String?,
      userAvatar: userObj?['avatar_url'] as String? ?? json['user_avatar'] as String?,
      role: json['role'] as String? ?? 'member',
      status: PresenceStatus.fromString(json['status'] as String?),
      lastVerifiedAt: json['last_verified_at'] != null
          ? DateTime.parse(json['last_verified_at'] as String)
          : null,
      deviceFingerprint: json['device_fingerprint'] as String?,
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'user_id': userId,
      'role': role,
      'status': status.dbValue,
      'last_verified_at': lastVerifiedAt?.toIso8601String(),
      'device_fingerprint': deviceFingerprint,
      'joined_at': joinedAt.toIso8601String(),
    };
  }

  SessionMemberModel copyWith({
    String? id,
    String? sessionId,
    String? userId,
    String? userName,
    String? userPhone,
    String? userEmail,
    String? userAvatar,
    String? role,
    PresenceStatus? status,
    DateTime? lastVerifiedAt,
    String? deviceFingerprint,
  }) {
    return SessionMemberModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      userEmail: userEmail ?? this.userEmail,
      userAvatar: userAvatar ?? this.userAvatar,
      role: role ?? this.role,
      status: status ?? this.status,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      deviceFingerprint: deviceFingerprint ?? this.deviceFingerprint,
      joinedAt: joinedAt,
    );
  }
}
