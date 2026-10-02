import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = true;
  String? _authError;
  StreamSubscription<AuthState>? _authSubscription;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;
  String? get authError => _authError;

  void setMockUser(UserModel user) {
    _currentUser = user;
    _isLoading = false;
    notifyListeners();
  }

  AuthProvider() {
    _initAuthSession();
  }

  bool _isSupabaseInitialized() {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initAuthSession() async {
    _isLoading = true;
    notifyListeners();

    if (!_isSupabaseInitialized()) {
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      final authUser = client.auth.currentUser;

      if (session != null && authUser != null) {
        await _loadUserProfile(authUser);
      } else {
        _currentUser = null;
      }

      // Listen to auth state transitions
      await _authSubscription?.cancel();
      _authSubscription = client.auth.onAuthStateChange.listen((data) async {
        final event = data.event;
        final changedUser = data.session?.user;

        if (event == AuthChangeEvent.signedIn && changedUser != null) {
          await _loadUserProfile(changedUser);
        } else if (event == AuthChangeEvent.signedOut) {
          _currentUser = null;
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('Auth initialization error: $e');
      _currentUser = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUserProfile(User authUser) async {
    try {
      final client = Supabase.instance.client;
      final profile = await client
          .from('users')
          .select()
          .eq('auth_id', authUser.id)
          .maybeSingle();

      if (profile != null) {
        _currentUser = UserModel(
          id: profile['id'] as String? ?? authUser.id,
          name: profile['name'] as String? ??
              authUser.userMetadata?['name'] as String? ??
              authUser.email?.split('@').first ??
              'User',
          email: profile['email'] as String? ?? authUser.email,
          phone: profile['phone'] as String? ?? authUser.userMetadata?['phone'] as String?,
          avatarUrl: profile['avatar_url'] as String?,
        );
      } else {
        // Fallback to auth metadata if user row is not yet provisioned
        final fallbackName = authUser.userMetadata?['name'] as String? ??
            authUser.email?.split('@').first ??
            'User';
        final fallbackPhone = authUser.userMetadata?['phone'] as String?;

        _currentUser = UserModel(
          id: authUser.id,
          name: fallbackName,
          email: authUser.email,
          phone: fallbackPhone,
        );

        // Auto-provision user record in public.users table
        try {
          await client.from('users').insert({
            'id': authUser.id,
            'auth_id': authUser.id,
            'name': fallbackName,
            'email': authUser.email,
            'phone': fallbackPhone,
          });
        } catch (dbErr) {
          debugPrint('Notice during user auto-provision: $dbErr');
        }
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
      _currentUser = UserModel(
        id: authUser.id,
        name: authUser.userMetadata?['name'] as String? ??
            authUser.email?.split('@').first ??
            'User',
        email: authUser.email,
        phone: authUser.userMetadata?['phone'] as String?,
      );
    }
    notifyListeners();
  }

  void clearError() {
    _authError = null;
    notifyListeners();
  }

  /// Create a new account with email, password, and profile data in Supabase
  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      if (!_isSupabaseInitialized()) {
        throw Exception('Supabase service is not initialized.');
      }

      final client = Supabase.instance.client;
      final res = await client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'name': name.trim(), 'phone': phone?.trim()},
      );

      final authUser = res.user;
      if (authUser == null) {
        throw Exception('Account creation failed. Please check your details and try again.');
      }

      final userId = const Uuid().v4();
      try {
        await client.from('users').upsert({
          'id': userId,
          'auth_id': authUser.id,
          'name': name.trim(),
          'email': email.trim(),
          'phone': phone?.trim(),
        });
      } catch (dbErr) {
        debugPrint('User table sync note: $dbErr');
      }

      _currentUser = UserModel(
        id: userId,
        name: name.trim(),
        email: email.trim(),
        phone: phone?.trim(),
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = _formatError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Sign in with email and password via Supabase Auth
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      if (!_isSupabaseInitialized()) {
        throw Exception('Supabase service is not initialized.');
      }

      final client = Supabase.instance.client;
      final res = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final authUser = res.user;
      if (authUser == null) {
        throw Exception('Sign-in failed. Please verify credentials.');
      }

      await _loadUserProfile(authUser);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = _formatError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  String _formatError(dynamic e) {
    final str = e.toString();
    return str
        .replaceFirst('AuthException(message: ', '')
        .replaceFirst('Exception: ', '')
        .replaceAll(RegExp(r', statusCode: [0-9]+'), '')
        .replaceAll(')', '');
  }

  Future<void> updateProfile({
    required String name,
    String? phone,
    String? email,
  }) async {
    if (_currentUser == null) return;

    _currentUser = _currentUser!.copyWith(
      name: name,
      phone: phone,
      email: email,
    );

    if (_isSupabaseInitialized()) {
      try {
        final client = Supabase.instance.client;
        final updateData = <String, dynamic>{
          'name': name,
          'phone': phone,
        };
        if (email != null) {
          updateData['email'] = email;
        }
        await client.from('users').update(updateData).eq('id', _currentUser!.id);
      } catch (e) {
        debugPrint('Profile update sync error: $e');
      }
    }

    notifyListeners();
  }

  Future<void> signOut() async {
    if (_isSupabaseInitialized()) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        debugPrint('Sign-out error: $e');
      }
    }

    _currentUser = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
