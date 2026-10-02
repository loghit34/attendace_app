import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../models/presence_check_model.dart';
import '../models/presence_event_model.dart';
import '../models/session_member_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import '../utils/join_code_helper.dart';
import 'anti_fraud_service.dart';

abstract class SessionService {
  Future<SessionModel> createSession(SessionModel session);
  Future<SessionModel?> getSession(String sessionId);
  Future<SessionModel?> getSessionByCode(String joinCode);
  Future<List<SessionModel>> getUserSessions(String userId);
  Future<SessionMemberModel> joinSession({
    required String sessionId,
    required UserModel user,
    String role = 'member',
  });
  Future<List<SessionMemberModel>> getSessionMembers(String sessionId);
  Stream<List<SessionMemberModel>> streamSessionMembers(String sessionId);
  Future<PresenceCheckModel> startPresenceCheck({
    required String sessionId,
    required String organizerId,
  });
  Future<PresenceCheckModel?> getActivePresenceCheck(String sessionId);
  Future<bool> verifyMemberPresence({
    required String sessionId,
    required String checkId,
    required String userId,
    required String token,
    String method = 'ble',
    int? rssi,
  });
  Future<void> updateMemberStatus({
    required String sessionId,
    required String userId,
    required PresenceStatus status,
  });
  Future<void> endSession(String sessionId);
  Future<void> leaveSession({
    required String sessionId,
    required String userId,
  });
  Future<List<PresenceEventModel>> getSessionEvents(String sessionId);
  Stream<PresenceEventModel> streamSessionEvents(String sessionId);
}

/// Supabase production implementation
class SupabaseSessionService implements SessionService {
  SupabaseClient? get client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  final StreamController<PresenceEventModel> _eventStream =
      StreamController<PresenceEventModel>.broadcast();

  // Resilience & offline cache: prevents app hangs/crashes during database RLS recursion or connection loss
  static final Map<String, SessionModel> _cachedSessions = {};
  static final Map<String, List<SessionMemberModel>> _cachedMembers = {};
  static final Map<String, List<PresenceEventModel>> _cachedEvents = {};
  static final Map<String, PresenceCheckModel> _cachedChecks = {};

  /// Ensures user record is present in public.users to satisfy foreign key constraints
  Future<void> _ensureUserRecord({
    required SupabaseClient client,
    required String userId,
    String? name,
    String? email,
    String? phone,
  }) async {
    try {
      final authId = client.auth.currentUser?.id ?? userId;
      await client.from('users').upsert({
        'id': userId,
        'auth_id': authId,
        'name': name?.trim().isNotEmpty == true ? name!.trim() : 'User',
        'email': email?.trim(),
        'phone': phone?.trim(),
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('[Diagnostic] _ensureUserRecord notice: $e');
    }
  }

  @override
  Future<SessionModel> createSession(SessionModel session) async {
    // Standardize join code format
    final normalizedCode = JoinCodeHelper.normalize(session.joinCode);
    SessionModel created = session.copyWith(joinCode: normalizedCode);

    // 1. Attempt database creation in Supabase
    final c = client;
    if (c != null) {
      try {
        // Guarantee that the organizer user record exists in public.users first
        await _ensureUserRecord(
          client: c,
          userId: session.organizerId,
          name: 'Organizer',
        );

        Map<String, dynamic> insertPayload = created.toJson(includeProximity: false);

        dynamic response;
        try {
          response = await c
              .from('sessions')
              .insert(insertPayload)
              .select()
              .single();
        } catch (insertErr) {
          debugPrint('[Diagnostic] Primary session insert note: $insertErr. Retrying with minimal essential fields...');
          insertPayload = {
            'id': created.id,
            'organizer_id': created.organizerId,
            'name': created.name,
            'category': created.category,
            'join_code': created.joinCode,
            'start_time': created.startTime.toIso8601String(),
            'end_time': created.endTime.toIso8601String(),
            'status': created.status,
          };
          response = await c
              .from('sessions')
              .insert(insertPayload)
              .select()
              .single();
        }

        created = SessionModel.fromJson(response);
        debugPrint('[Diagnostic] Session successfully committed to Supabase: id=${created.id}, join_code=${created.joinCode}, status=${created.status}');
      } catch (e) {
        debugPrint('[Diagnostic] Supabase createSession error: $e. Using local resilient session.');
      }
    }

    _cachedSessions[created.id] = created;

    // 2. Auto add organizer as member locally
    final organizerMember = SessionMemberModel(
      id: const Uuid().v4(),
      sessionId: created.id,
      userId: created.organizerId,
      userName: 'Organizer (You)',
      role: 'organizer',
      status: PresenceStatus.present,
      lastVerifiedAt: DateTime.now(),
      joinedAt: DateTime.now(),
    );

    final members = _cachedMembers[created.id] ?? [];
    if (!members.any((m) => m.userId == created.organizerId)) {
      members.add(organizerMember);
    }
    _cachedMembers[created.id] = members;

    // 3. Attempt database member insertion
    if (c != null) {
      try {
        await c.from('session_members').upsert({
          'session_id': created.id,
          'user_id': created.organizerId,
          'role': 'organizer',
          'status': 'present',
          'last_verified_at': DateTime.now().toIso8601String(),
          'joined_at': DateTime.now().toIso8601String(),
        }, onConflict: 'session_id,user_id');
      } catch (e) {
        debugPrint('[Diagnostic] Supabase auto add organizer note: $e');
      }
    }

    // 4. Log event
    try {
      await _logEvent(
        sessionId: created.id,
        userId: created.organizerId,
        eventType: 'created_session',
      );
    } catch (_) {}

    return created;
  }

  @override
  Future<SessionModel?> getSession(String sessionId) async {
    final c = client;
    if (c != null) {
      try {
        final response = await c
            .from('sessions')
            .select()
            .eq('id', sessionId)
            .maybeSingle();

        if (response != null) {
          final session = SessionModel.fromJson(response);
          _cachedSessions[sessionId] = session;
          return session;
        }
      } catch (e) {
        debugPrint('[Diagnostic] Supabase getSession note: $e');
      }
    }

    return _cachedSessions[sessionId];
  }

  @override
  Future<SessionModel?> getSessionByCode(String joinCode) async {
    final normalized = JoinCodeHelper.normalize(joinCode);
    final c = client;

    debugPrint('[Diagnostic] ========================================');
    debugPrint('[Diagnostic] Session Lookup Initiated');
    debugPrint('[Diagnostic]   ENTERED_CODE: "$joinCode"');
    debugPrint('[Diagnostic]   NORMALIZED_CODE: "$normalized"');
    debugPrint('[Diagnostic]   DATABASE_COLUMN_USED: "join_code"');
    debugPrint('[Diagnostic]   AUTH_STATUS: ${c?.auth.currentUser != null ? "Authenticated (${c!.auth.currentUser!.id})" : "Anonymous/Unauthenticated"}');

    if (c != null) {
      try {
        // 1. Primary lookup by exact normalized join_code
        var response = await c
            .from('sessions')
            .select()
            .eq('join_code', normalized)
            .maybeSingle();

        // 2. If not found and input matches UUID format, check id column
        if (response == null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(joinCode.trim())) {
          debugPrint('[Diagnostic] Checking session by id column for UUID: ${joinCode.trim()}');
          response = await c
              .from('sessions')
              .select()
              .eq('id', joinCode.trim())
              .maybeSingle();
        }

        // 3. Fallback: case-insensitive ilike lookup
        if (response == null) {
          response = await c
              .from('sessions')
              .select()
              .ilike('join_code', normalized)
              .maybeSingle();
        }

        if (response != null) {
          final session = SessionModel.fromJson(response);
          _cachedSessions[session.id] = session;
          debugPrint('[Diagnostic]   QUERY_RESULT: FOUND');
          debugPrint('[Diagnostic]   SESSION_ID: ${session.id}');
          debugPrint('[Diagnostic]   SESSION_STATUS: ${session.status}');
          debugPrint('[Diagnostic]   IS_ACTIVE: ${session.isActive}');
          debugPrint('[Diagnostic]   START_TIME: ${session.startTime}');
          debugPrint('[Diagnostic]   EXPIRATION_TIME: ${session.endTime}');
          debugPrint('[Diagnostic] ========================================');
          return session;
        } else {
          debugPrint('[Diagnostic]   QUERY_RESULT: NOT_FOUND in Supabase for join_code="$normalized"');
        }
      } catch (e) {
        debugPrint('[Diagnostic] Supabase getSessionByCode query error: $e');
      }
    }

    // Local in-memory cache lookup
    try {
      final session = _cachedSessions.values.firstWhere(
        (s) =>
            JoinCodeHelper.normalize(s.joinCode) == normalized ||
            s.id == joinCode.trim() ||
            s.joinCode.toUpperCase() == normalized,
      );
      debugPrint('[Diagnostic]   QUERY_RESULT: FOUND in local cache (session_id=${session.id})');
      debugPrint('[Diagnostic] ========================================');
      return session;
    } catch (_) {
      debugPrint('[Diagnostic]   QUERY_RESULT: NOT_FOUND in local cache');
      debugPrint('[Diagnostic] ========================================');
      return null;
    }
  }

  @override
  Future<List<SessionModel>> getUserSessions(String userId) async {
    final Map<String, SessionModel> sessionsMap = Map.from(_cachedSessions);
    final c = client;

    if (c != null) {
      try {
        final response = await c
            .from('session_members')
            .select('session_id, sessions(*)')
            .eq('user_id', userId)
            .order('joined_at', ascending: false);

        for (final item in response as List) {
          if (item['sessions'] != null) {
            final s = SessionModel.fromJson(item['sessions'] as Map<String, dynamic>);
            sessionsMap[s.id] = s;
          }
        }
      } catch (e) {
        debugPrint('[Diagnostic] getUserSessions query note: $e');
        try {
          final response = await c
              .from('sessions')
              .select()
              .order('created_at', ascending: false);

          for (final item in response as List) {
            final s = SessionModel.fromJson(item as Map<String, dynamic>);
            sessionsMap[s.id] = s;
          }
        } catch (e2) {
          debugPrint('[Diagnostic] getUserSessions fallback note: $e2');
        }
      }
    }

    final list = sessionsMap.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<SessionMemberModel> joinSession({
    required String sessionId,
    required UserModel user,
    String role = 'member',
  }) async {
    final memberId = const Uuid().v4();
    final newMember = SessionMemberModel(
      id: memberId,
      sessionId: sessionId,
      userId: user.id,
      userName: user.name,
      userPhone: user.phone,
      userEmail: user.email,
      role: role,
      status: PresenceStatus.missing,
      joinedAt: DateTime.now(),
    );

    // 1. Update local cache immediately (preserve verified status if already present)
    final members = _cachedMembers[sessionId] ?? [];
    final existingIdx = members.indexWhere((m) => m.userId == user.id);
    if (existingIdx != -1) {
      final existing = members[existingIdx];
      members[existingIdx] = existing.copyWith(
        userName: user.name,
        userPhone: user.phone,
        userEmail: user.email,
        role: role,
      );
    } else {
      members.add(newMember);
    }
    _cachedMembers[sessionId] = members;

    // 2. Attempt Supabase upsert
    final c = client;
    if (c != null) {
      try {
        // Guarantee user record exists in public.users to satisfy FK constraint
        await _ensureUserRecord(
          client: c,
          userId: user.id,
          name: user.name,
          email: user.email,
          phone: user.phone,
        );

        final data = {
          'session_id': sessionId,
          'user_id': user.id,
          'role': role,
          'status': 'missing',
          'joined_at': DateTime.now().toIso8601String(),
        };

        final response = await c
            .from('session_members')
            .upsert(data, onConflict: 'session_id,user_id')
            .select()
            .single();

        final parsed = SessionMemberModel.fromJson(response);
        final idx = members.indexWhere((m) => m.userId == user.id);
        if (idx != -1) members[idx] = parsed;
        debugPrint('[Diagnostic] Successfully saved membership for user ${user.id} in session $sessionId');
        return parsed;
      } catch (e) {
        debugPrint('[Diagnostic] Supabase joinSession note: $e');
      } finally {
        _logEvent(
          sessionId: sessionId,
          userId: user.id,
          eventType: 'joined',
          userName: user.name,
        );
      }
    }
    return newMember;
  }

  @override
  Future<List<SessionMemberModel>> getSessionMembers(String sessionId) async {
    final c = client;
    if (c != null) {
      try {
        final response = await c
            .from('session_members')
            .select('*, users(name, email, phone, avatar_url)')
            .eq('session_id', sessionId)
            .order('joined_at', ascending: true);

        final list = (response as List)
            .map((e) => SessionMemberModel.fromJson(e as Map<String, dynamic>))
            .toList();

        if (list.isNotEmpty) {
          _cachedMembers[sessionId] = list;
          return list;
        }
      } catch (e) {
        debugPrint('Supabase getSessionMembers note: $e');
      }
    }

    return _cachedMembers[sessionId] ?? [];
  }

  @override
  Stream<List<SessionMemberModel>> streamSessionMembers(String sessionId) {
    final c = client;
    if (c != null) {
      try {
        return c
            .from('session_members')
            .stream(primaryKey: ['id'])
            .eq('session_id', sessionId)
            .asyncMap((list) async {
              return await getSessionMembers(sessionId);
            })
            .handleError((err) {
              debugPrint('Live session stream note: $err');
            });
      } catch (e) {
        debugPrint('streamSessionMembers startup note: $e');
      }
    }
    return Stream.value(_cachedMembers[sessionId] ?? []);
  }

  @override
  Future<PresenceCheckModel> startPresenceCheck({
    required String sessionId,
    required String organizerId,
  }) async {
    final checkId = const Uuid().v4();
    final now = DateTime.now();
    final expiresAt = now.add(AppConfig.checkTokenDuration);

    final token = AntiFraudService.generatePresenceToken(
      sessionId: sessionId,
      checkId: checkId,
      timestamp: now,
    );

    final localCheck = PresenceCheckModel(
      id: checkId,
      sessionId: sessionId,
      initiatorId: organizerId,
      checkToken: token,
      status: 'active',
      startedAt: now,
      expiresAt: expiresAt,
    );

    _cachedChecks[sessionId] = localCheck;

    final c = client;
    if (c != null) {
      try {
        final checkData = {
          'id': checkId,
          'session_id': sessionId,
          'initiator_id': organizerId,
          'check_token': token,
          'status': 'active',
          'started_at': now.toIso8601String(),
          'expires_at': expiresAt.toIso8601String(),
        };

        final response = await c
            .from('presence_checks')
            .insert(checkData)
            .select()
            .single();

        final savedCheck = PresenceCheckModel.fromJson(response);
        _cachedChecks[sessionId] = savedCheck;

        await _logEvent(
          sessionId: sessionId,
          userId: organizerId,
          eventType: 'check_started',
        );

        return savedCheck;
      } catch (e) {
        debugPrint('Supabase startPresenceCheck note: $e');
      }
    }
    return localCheck;
  }

  @override
  Future<PresenceCheckModel?> getActivePresenceCheck(String sessionId) async {
    final c = client;
    if (c != null) {
      try {
        final now = DateTime.now().toIso8601String();
        final response = await c
            .from('presence_checks')
            .select()
            .eq('session_id', sessionId)
            .eq('status', 'active')
            .gt('expires_at', now)
            .order('started_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (response != null) {
          final check = PresenceCheckModel.fromJson(response);
          _cachedChecks[sessionId] = check;
          return check;
        }
      } catch (e) {
        debugPrint('Supabase getActivePresenceCheck note: $e');
      }
    }

    final cached = _cachedChecks[sessionId];
    if (cached != null && !cached.isExpired && cached.status == 'active') {
      return cached;
    }
    return null;
  }

  @override
  Future<bool> verifyMemberPresence({
    required String sessionId,
    required String checkId,
    required String userId,
    required String token,
    String method = 'ble',
    int? rssi,
  }) async {
    final now = DateTime.now();

    // 1. Group membership validation: User MUST be an enrolled member of this session
    final cachedMemberList = _cachedMembers[sessionId] ?? [];
    final isEnrolledLocally = cachedMemberList.any((m) => m.userId == userId);
    final existingMember = cachedMemberList.cast<SessionMemberModel?>().firstWhere(
      (m) => m != null && m.userId == userId,
      orElse: () => null,
    );

    // If member is already verified as present for this session, repeated BLE detections are idempotent
    if (existingMember != null && existingMember.status == PresenceStatus.present) {
      return true;
    }

    final c = client;
    if (c != null) {
      try {
        final memberRes = await c
            .from('session_members')
            .select('id')
            .eq('session_id', sessionId)
            .eq('user_id', userId)
            .maybeSingle();

        if (memberRes == null && !isEnrolledLocally) {
          debugPrint('Presence verification rejected: User is not enrolled in session $sessionId.');
          return false;
        }
      } catch (e) {
        debugPrint('Supabase verifyMemberPresence enrollment check note: $e');
        if (!isEnrolledLocally) {
          debugPrint('Presence verification rejected: User is not enrolled in local cache.');
          return false;
        }
      }
    } else {
      if (!isEnrolledLocally) {
        debugPrint('Presence verification rejected: User is not enrolled in session.');
        return false;
      }
    }

    // 2. Fetch active check and validate existence & expiry
    PresenceCheckModel? check = _cachedChecks[sessionId];
    if (c != null) {
      try {
        final checkRes = await c
            .from('presence_checks')
            .select()
            .eq('id', checkId)
            .eq('session_id', sessionId)
            .eq('status', 'active')
            .maybeSingle();

        if (checkRes != null) {
          check = PresenceCheckModel.fromJson(checkRes);
          _cachedChecks[sessionId] = check;
        }
      } catch (e) {
        debugPrint('Supabase verifyMemberPresence check lookup note: $e');
      }
    }

    if (check == null || check.id != checkId || check.isExpired || check.sessionId != sessionId) {
      debugPrint('Presence verification rejected: Check does not exist, belongs to different session, or has expired.');
      return false;
    }

    // 3. Token match validation
    if (check.checkToken != token && !token.contains(check.checkToken)) {
      debugPrint('Presence verification rejected: Token mismatch ($token != ${check.checkToken}).');
      return false;
    }

    // 4. Anti-fraud server-side validation
    final verification = AntiFraudService.verifyProof(
      sessionId: sessionId,
      checkId: checkId,
      memberId: userId,
      receivedToken: token,
      checkExpiresAt: check.expiresAt,
      proofTimestamp: now,
    );

    if (!verification.isValid) {
      debugPrint('Presence verification rejected: Token invalid (${verification.failureReason}).');
      return false;
    }

    // 5. Attempt Supabase RPC execution if available
    if (c != null) {
      try {
        // Try modern universal RPC name first
        dynamic rpcRes;
        try {
          rpcRes = await c.rpc('record_bluetooth_presence', params: {
            'p_session_id': sessionId,
            'p_check_id': checkId,
            'p_user_id': userId,
            'p_token': token,
            'p_method': method,
            'p_rssi': rssi,
          });
        } catch (_) {
          // Fallback to alias if database migration is pending
          rpcRes = await c.rpc('record_bluetooth_attendance', params: {
            'p_session_id': sessionId,
            'p_check_id': checkId,
            'p_user_id': userId,
            'p_token': token,
            'p_method': method,
            'p_rssi': rssi,
          });
        }

        if (rpcRes is Map && rpcRes['success'] == false) {
          debugPrint('RPC presence verification error: ${rpcRes['error']}');
          return false;
        }
      } catch (e) {
        debugPrint('Supabase record_bluetooth_presence rpc note: $e');
      }
    }

    // 6. Update member status only after passing check validation
    await updateMemberStatus(
      sessionId: sessionId,
      userId: userId,
      status: PresenceStatus.present,
    );

    // 7. Record verification and log event
    if (c != null) {
      try {
        await c.from('presence_verifications').upsert({
          'check_id': checkId,
          'session_id': sessionId,
          'user_id': userId,
          'verification_token_hash': verification.tokenHash,
          'verification_method': method,
          'verified_at': now.toIso8601String(),
          'rssi': rssi,
        }, onConflict: 'check_id,user_id');

        await _logEvent(
          sessionId: sessionId,
          userId: userId,
          eventType: 'verified_ble',
          metadata: {'rssi': rssi, 'method': method},
        );
      } catch (e) {
        debugPrint('Supabase verifyMemberPresence note: $e');
      }
    }

    return true;
  }

  @override
  Future<void> updateMemberStatus({
    required String sessionId,
    required String userId,
    required PresenceStatus status,
  }) async {
    // 1. Instant local cache update
    final members = _cachedMembers[sessionId] ?? [];
    final idx = members.indexWhere((m) => m.userId == userId);
    if (idx != -1) {
      members[idx] = members[idx].copyWith(
        status: status,
        lastVerifiedAt: (status == PresenceStatus.present ||
                status == PresenceStatus.manuallyConfirmed)
            ? DateTime.now()
            : members[idx].lastVerifiedAt,
      );
      _cachedMembers[sessionId] = members;
    }

    // 2. Persist to Supabase
    final c = client;
    if (c != null) {
      try {
        await c.from('session_members').update({
          'status': status.dbValue,
          'last_verified_at': status == PresenceStatus.present ||
                  status == PresenceStatus.manuallyConfirmed
              ? DateTime.now().toIso8601String()
              : null,
        }).match({'session_id': sessionId, 'user_id': userId});

        await _logEvent(
          sessionId: sessionId,
          userId: userId,
          eventType: status == PresenceStatus.manuallyConfirmed
              ? 'manually_confirmed'
              : status == PresenceStatus.missing
                  ? 'marked_missing'
                  : 'status_updated',
        );
      } catch (e) {
        debugPrint('Supabase updateMemberStatus note: $e');
      }
    }
  }

  @override
  Future<void> endSession(String sessionId) async {
    final cached = _cachedSessions[sessionId];
    if (cached != null) {
      _cachedSessions[sessionId] = cached.copyWith(status: 'completed');
    }

    final c = client;
    if (c != null) {
      try {
        await c
            .from('sessions')
            .update({'status': 'completed'}).eq('id', sessionId);
      } catch (e) {
        debugPrint('Supabase endSession note: $e');
      }
    }

    await _logEvent(
      sessionId: sessionId,
      eventType: 'session_ended',
    );
  }

  @override
  Future<void> leaveSession({
    required String sessionId,
    required String userId,
  }) async {
    await updateMemberStatus(
      sessionId: sessionId,
      userId: userId,
      status: PresenceStatus.left,
    );

    await _logEvent(
      sessionId: sessionId,
      userId: userId,
      eventType: 'left_session',
    );
  }

  @override
  Future<List<PresenceEventModel>> getSessionEvents(String sessionId) async {
    final c = client;
    if (c != null) {
      try {
        final response = await c
            .from('presence_events')
            .select()
            .eq('session_id', sessionId)
            .order('created_at', ascending: false)
            .limit(50);

        return (response as List)
            .map((e) => PresenceEventModel.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Supabase getSessionEvents note: $e');
      }
    }

    return _cachedEvents[sessionId] ?? [];
  }

  @override
  Stream<PresenceEventModel> streamSessionEvents(String sessionId) {
    return _eventStream.stream.where((e) => e.sessionId == sessionId);
  }

  Future<void> _logEvent({
    required String sessionId,
    String? userId,
    String? userName,
    required String eventType,
    Map<String, dynamic> metadata = const {},
  }) async {
    final event = PresenceEventModel(
      id: const Uuid().v4(),
      sessionId: sessionId,
      userId: userId,
      userName: userName,
      eventType: eventType,
      createdAt: DateTime.now(),
      metadata: metadata,
    );

    final events = _cachedEvents[sessionId] ?? [];
    events.insert(0, event);
    _cachedEvents[sessionId] = events;
    _eventStream.add(event);

    final c = client;
    if (c != null) {
      try {
        await c.from('presence_events').insert({
          'session_id': sessionId,
          'user_id': userId,
          'event_type': eventType,
          'metadata': metadata,
        });
      } catch (e) {
        debugPrint('Log event warning: $e');
      }
    }
  }
}
