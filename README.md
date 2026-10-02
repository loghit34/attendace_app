# HereNow 📍

> **"Know who's here, without calling everyone."**

**HereNow** is a temporary group-presence verification mobile application built with **Flutter**, **Dart**, **Supabase**, and **Bluetooth Low Energy (BLE)**.

Unlike traditional school attendance or employee surveillance systems, HereNow is designed around temporary, privacy-respecting presence checks for groups on the move:
* Company retreats & offsites
* Tour groups & bus transfers
* Sports teams & coaches
* Family trips & gatherings
* Event & conference staff
* Field operations & volunteer crews

---

## 📱 Core Features

### 1. Dynamic Roles (Organizer & Member)
* No rigid Student/Teacher or Admin hierarchies. Any user can be an **Organizer** for one session (e.g. organizing a weekend trek) and a **Member** for another (e.g. attending a company all-hands).
* **Organizer:** Create temporary sessions, display QR/code, start BLE presence pulse, monitor real-time 28/30 headcount dashboard, manually confirm members, call/SMS missing people, export CSV reports.
* **Member:** Join via 6-digit code (`HN-482731`) or QR code, automatic BLE verification pulse response, see verified status, leave session anytime.

### 2. Live Organizer Dashboard
* High-visibility **28 / 30 Present** headcount cards with interactive status filters.
* 5 distinct presence states:
  * 🟢 **PRESENT**: Verified recently via BLE challenge pulse
  * 🟡 **POSSIBLY AWAY**: Previously detected, verification expired
  * 🔴 **MISSING**: Not detected in active check window
  * 🔵 **MANUALLY CONFIRMED**: Verified in-person by organizer
  * ⚪ **LEFT**: Explicitly left or departed group
* Real-time search, quick calling/SMS shortcut for missing members, and audit log.

### 3. Ephemeral BLE Verification Pipeline
1. Organizer taps **Start Presence Check**.
2. A cryptographic rotating verification token is minted (HMAC-SHA256, 60-second validity).
3. Organizer broadcasts the ephemeral token beacon over BLE.
4. Nearby member devices listen and generate a signed verification proof.
5. Proof is verified by backend against clock skew, expiry, and replay defenses.
6. Realtime headcount updates dynamically across all organizer dashboards.

### 4. Privacy & Anti-Fraud Architecture
* **Zero Permanent Tracking:** No continuous background GPS logging.
* **Ephemeral Tokens:** Expire within 60 seconds; immune to replay attacks.
* **Platform Friendly:** Respects Android and iOS background execution and BLE privacy limits (avoids reliance on persistent hardware MACs).
* **Optional Geofence:** Configurable radius (30m - 500m) for location-bound checkpoints.

---

## 🗄️ Database Architecture (Supabase)

HereNow connects to Supabase with PostgreSQL Row-Level Security (RLS) and Realtime subscriptions.

### Tables
* `public.users`: Profiles (name, phone, avatar)
* `public.sessions`: Temporary groups (`id`, `organizer_id`, `name`, `category`, `join_code`, `start_time`, `end_time`, `status`)
* `public.session_members`: Session-scoped participation (`session_id`, `user_id`, `role`, `status`, `last_verified_at`)
* `public.presence_checks`: Rotating ephemeral checks (`check_token`, `status`, `expires_at`)
* `public.presence_verifications`: Individual cryptographic verification proofs
* `public.presence_events`: Real-time audit trail

*The complete PostgreSQL script with RLS policies and Realtime triggers is located at `supabase/schema.sql`.*

---

## 🚀 Running HereNow

### Prerequisites
* Flutter SDK (3.13+)
* Android Studio / Xcode for mobile deployment

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Run Tests
```bash
flutter test
```

### 3. Run Application
```bash
# Run on Chrome / Web
flutter run -d chrome

# Run on Android Device / Emulator
flutter run -d <android-device-id>

# Run on iOS Device / Simulator
flutter run -d <ios-device-id>
```

---

## 🧪 Interactive Demo Mode
HereNow includes an offline **Demo Mode** seeded with the exact *Company Trip — Digha* scenario:
* **30 members** (28 present, 2 missing: Rohan Mehta and Arjun Kapoor).
* Simulated BLE discovery pulse when tapping **Check Again**.
* One-click role switcher between Organizer and Member views in Settings and Home.
* Toggle between Demo Mode and Live Supabase backend anytime in the Settings screen.
