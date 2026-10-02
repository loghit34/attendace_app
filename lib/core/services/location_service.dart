import 'dart:math';

class LocationCheckResult {
  final bool isWithinGeofence;
  final double distanceMeters;
  final String? message;

  LocationCheckResult({
    required this.isWithinGeofence,
    required this.distanceMeters,
    this.message,
  });
}

class LocationService {
  /// Calculates distance in meters between two coordinates using the Haversine formula
  static double calculateDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusMeters = 6371000;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _degToRad(double deg) {
    return deg * (pi / 180.0);
  }

  /// Verifies if a user's location is within the organizer's session geofence
  static LocationCheckResult verifyGeofence({
    required double userLat,
    required double userLon,
    required double meetingLat,
    required double meetingLon,
    required double geofenceRadiusMeters,
  }) {
    final distance = calculateDistanceMeters(userLat, userLon, meetingLat, meetingLon);
    final isWithin = distance <= geofenceRadiusMeters;

    return LocationCheckResult(
      isWithinGeofence: isWithin,
      distanceMeters: distance,
      message: isWithin
          ? 'Within geofence (${distance.toStringAsFixed(1)}m from meeting point)'
          : 'Outside geofence (${distance.toStringAsFixed(1)}m > ${geofenceRadiusMeters.toStringAsFixed(0)}m radius)',
    );
  }
}
