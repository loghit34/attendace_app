enum ProximityMode {
  near(-65, 'Near (~1-3 meters)'),
  normal(-75, 'Normal (~5-10 meters)'),
  wide(-85, 'Wide (~15-25 meters)');

  final int rssiThreshold;
  final String label;

  const ProximityMode(this.rssiThreshold, this.label);

  static ProximityMode fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'near':
        return ProximityMode.near;
      case 'wide':
        return ProximityMode.wide;
      case 'normal':
      default:
        return ProximityMode.normal;
    }
  }

  String get dbValue {
    switch (this) {
      case ProximityMode.near:
        return 'near';
      case ProximityMode.wide:
        return 'wide';
      case ProximityMode.normal:
        return 'normal';
    }
  }
}

enum GroupType {
  company('COMPANY', 'Company / Work'),
  travel('TRAVEL', 'Travel / Tour Group'),
  education('EDUCATION', 'Education / Class'),
  event('EVENT', 'Event / Conference'),
  sports('SPORTS', 'Sports Team / Club'),
  club('CLUB', 'Club / Community'),
  friends('FRIENDS', 'Friends Group'),
  family('FAMILY', 'Family Gathering'),
  other('OTHER', 'General Group');

  final String code;
  final String displayName;

  const GroupType(this.code, this.displayName);

  static GroupType fromString(String? val) {
    if (val == null) return GroupType.other;
    final normalized = val.toUpperCase().trim();
    for (final type in GroupType.values) {
      if (type.code == normalized || type.name.toUpperCase() == normalized) {
        return type;
      }
    }
    return GroupType.other;
  }
}

class AppConfig {
  static const String appName = 'HereNow';
  static const String appTagline = "Know who's here, without calling everyone.";

  // Supabase Configuration
  // Configured via compile-time environment variables (--dart-define) with production defaults
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qidgnaakasudrshtkwfo.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFpZGduYWFrYXN1ZHJzaHRrd2ZvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA2ODQ0MjcsImV4cCI6MjEwNjI2MDQyN30.Jx4CDQKsx5yncvpDxPchXmL0I9l7p6O7tm-ka5LuW0w',
  );

  // Bluetooth Low Energy Constants
  // Unique 128-bit Service UUID for HereNow Universal Presence Check
  static const String bleServiceUuid = '8f331900-1122-3344-5566-778899aabbcc';
  static const String bleTokenCharacteristicUuid = '8f331901-1122-3344-5566-778899aabbcc';
  static const String bleVerificationCharacteristicUuid = '8f331902-1122-3344-5566-778899aabbcc';

  // Verification Timeouts & Windows
  static const Duration checkTokenDuration = Duration(seconds: 60);
  static const Duration possiblyAwayThreshold = Duration(minutes: 3);
  static const Duration scanPulseDuration = Duration(seconds: 15);

  // Default RSSI threshold for Proximity Verification
  static const int defaultProximityRssi = -75;

  // Default geofence radius if organizer enables GPS verification
  static const double defaultGeofenceRadiusMeters = 100.0;
}
