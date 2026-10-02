import '../config/app_config.dart';

class SessionModel {
  final String id;
  final String organizerId;
  final String name;
  final String? description;
  final String category; // 'COMPANY', 'TRAVEL', 'EDUCATION', 'EVENT', 'SPORTS', 'CLUB', 'FRIENDS', 'FAMILY', 'OTHER'
  final String joinCode;
  final DateTime startTime;
  final DateTime endTime;
  final ProximityMode proximityMode;
  final double? meetingLatitude;
  final double? meetingLongitude;
  final double? geofenceRadius; // in meters
  final String status; // 'scheduled', 'active', 'completed'
  final DateTime createdAt;

  SessionModel({
    required this.id,
    required this.organizerId,
    required this.name,
    this.description,
    this.category = 'OTHER',
    required this.joinCode,
    required this.startTime,
    required this.endTime,
    this.proximityMode = ProximityMode.normal,
    this.meetingLatitude,
    this.meetingLongitude,
    this.geofenceRadius,
    this.status = 'active',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isExpired => DateTime.now().isAfter(endTime);
  bool get isActive => status == 'active' && !isExpired;
  bool get hasGeofence =>
      meetingLatitude != null && meetingLongitude != null && geofenceRadius != null && geofenceRadius! > 0;

  int get proximityThresholdRssi => proximityMode.rssiThreshold;

  GroupType get groupType => GroupType.fromString(category);

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      category: json['category'] as String? ?? 'OTHER',
      joinCode: json['join_code'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      proximityMode: ProximityMode.fromString(json['proximity_threshold'] as String?),
      meetingLatitude: (json['meeting_latitude'] as num?)?.toDouble(),
      meetingLongitude: (json['meeting_longitude'] as num?)?.toDouble(),
      geofenceRadius: (json['geofence_radius'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson({bool includeProximity = false}) {
    final map = <String, dynamic>{
      'id': id,
      'organizer_id': organizerId,
      'name': name,
      'description': description,
      'category': category,
      'join_code': joinCode,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'meeting_latitude': meetingLatitude,
      'meeting_longitude': meetingLongitude,
      'geofence_radius': geofenceRadius,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
    if (includeProximity) {
      map['proximity_threshold'] = proximityMode.dbValue;
    }
    return map;
  }

  SessionModel copyWith({
    String? id,
    String? organizerId,
    String? name,
    String? description,
    String? category,
    String? joinCode,
    DateTime? startTime,
    DateTime? endTime,
    ProximityMode? proximityMode,
    double? meetingLatitude,
    double? meetingLongitude,
    double? geofenceRadius,
    String? status,
  }) {
    return SessionModel(
      id: id ?? this.id,
      organizerId: organizerId ?? this.organizerId,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      joinCode: joinCode ?? this.joinCode,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      proximityMode: proximityMode ?? this.proximityMode,
      meetingLatitude: meetingLatitude ?? this.meetingLatitude,
      meetingLongitude: meetingLongitude ?? this.meetingLongitude,
      geofenceRadius: geofenceRadius ?? this.geofenceRadius,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}
