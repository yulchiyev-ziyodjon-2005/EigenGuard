import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Sprint 18 — Nexus auth & session manager (Mobile side).
///
/// Mobil ilova Nexus Web Panel'iga login qiladi, JWT token oladi va uni
/// xavfsiz tarzda saqlaydi (Android Keystore / iOS Keychain orqali
/// `flutter_secure_storage`). Login muvaffaqiyatli bo'lganda telefon
/// avtomatik ravishda Nexus'da Device sifatida ro'yxatga olinadi.
///
/// `NexusUploadService` va `NexusWsClient` shu servisdan `token`, `baseUrl`
/// va `tenantSubdomain` ni oladi — qo'lda kiritish endi kerak emas.
class NexusUser {
  final String id;
  final String username;
  final String email;
  final String? fullName;
  final String role;
  final bool isAdmin;
  final bool isSuperadmin;
  final String tenantId;
  final String tenantSubdomain;
  final String tenantName;
  final String deploymentMode;

  const NexusUser({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isAdmin,
    required this.isSuperadmin,
    required this.tenantId,
    required this.tenantSubdomain,
    required this.tenantName,
    required this.deploymentMode,
  });

  factory NexusUser.fromJson(Map<String, dynamic> json) => NexusUser(
        id: json['id'] as String,
        username: json['username'] as String? ?? json['email'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String?,
        role: json['role'] as String? ?? 'engineer',
        isAdmin: json['is_admin'] as bool? ?? false,
        isSuperadmin: json['is_superadmin'] as bool? ?? false,
        tenantId: json['tenant_id'] as String,
        tenantSubdomain: json['tenant_subdomain'] as String,
        tenantName: json['tenant_name'] as String,
        deploymentMode: json['deployment_mode'] as String,
      );

      Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'full_name': fullName,
        'role': role,
        'is_admin': isAdmin,
        'is_superadmin': isSuperadmin,
        'tenant_id': tenantId,
        'tenant_subdomain': tenantSubdomain,
        'tenant_name': tenantName,
        'deployment_mode': deploymentMode,
      };
}

class NexusAuthService {
  static final NexusAuthService _instance = NexusAuthService._();
  factory NexusAuthService() => _instance;
  NexusAuthService._();

  // ── Secure storage keys ─────────────────────────────────────────────
  static const _kBaseUrl = 'nexus.base_url';
  static const _kTenant = 'nexus.tenant_subdomain';
  static const _kEmail = 'nexus.email';
  static const _kToken = 'nexus.jwt_token';
  static const _kUserJson = 'nexus.user_json';
  static const _kDeviceId = 'nexus.device_identifier';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // ── Public observables ──────────────────────────────────────────────
  final ValueNotifier<NexusUser?> currentUser = ValueNotifier(null);
  final ValueNotifier<bool> initialized = ValueNotifier(false);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  String? _baseUrl;
  String? _tenant;
  String? _token;
  String? _deviceId;

  String? get baseUrl => _baseUrl;
  String? get tenantSubdomain => _tenant;
  String? get token => _token;
  String? get deviceIdentifier => _deviceId;
  bool get isAuthenticated => _token != null && currentUser.value != null;

  /// App startup'da chaqiriladi — saqlangan sessiya bo'lsa qayta tiklanadi.
  /// Token mavjudligini /auth/me orqali tasdiqlaydi.
  Future<void> bootstrap() async {
    if (initialized.value) return;
    try {
      _baseUrl = await _storage.read(key: _kBaseUrl);
      _tenant = await _storage.read(key: _kTenant);
      _token = await _storage.read(key: _kToken);
      _deviceId = await _ensureDeviceId();

      final userJson = await _storage.read(key: _kUserJson);
      if (userJson != null) {
        try {
          currentUser.value =
              NexusUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        } catch (_) {
          currentUser.value = null;
        }
      }

      if (_token != null && _baseUrl != null && _tenant != null) {
        // /auth/me orqali token amalda ekanini tekshiramiz
        final ok = await _refreshMe();
        if (!ok) {
          // Token eskirgan — silent logout
          await logout();
        }
      }
    } catch (e) {
      debugPrint('[NexusAuth] bootstrap err: $e');
    } finally {
      initialized.value = true;
    }
  }

  Future<String> _ensureDeviceId() async {
    var id = await _storage.read(key: _kDeviceId);
    if (id == null || id.isEmpty) {
      id = _generateUuid();
      await _storage.write(key: _kDeviceId, value: id);
    }
    return id;
  }

  static String _generateUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Nexus'ga login qilish. Muvaffaqiyatli bo'lsa Device ham
  /// avtomatik ravishda registratsiya qilinadi.
  Future<bool> login({
    required String baseUrl,
    required String tenantSubdomain,
    required String email,
    required String password,
  }) async {
    lastError.value = null;
    final normalizedBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final loginUri = Uri.parse('$normalizedBase/api/v1/auth/login');

    try {
      final resp = await http
          .post(
            loginUri,
            headers: {
              'Content-Type': 'application/json',
              'X-EigenGuard-Tenant': tenantSubdomain,
            },
            body: jsonEncode({
              'username': email,
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        lastError.value = _extractError(resp.body, fallback: 'Login xato');
        return false;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final token = body['access_token'] as String?;
      if (token == null || token.isEmpty) {
        lastError.value = 'Token kelmadi';
        return false;
      }

      // Saqlaymiz
      _baseUrl = normalizedBase;
      _tenant = tenantSubdomain;
      _token = token;
      _deviceId ??= await _ensureDeviceId();
      await _storage.write(key: _kBaseUrl, value: normalizedBase);
      await _storage.write(key: _kTenant, value: tenantSubdomain);
      await _storage.write(key: _kToken, value: token);
      await _storage.write(key: _kEmail, value: email);

      // /auth/me ni olamiz
      final ok = await _refreshMe();
      if (!ok) {
        lastError.value = '/auth/me dan ma\'lumot olib bo\'lmadi';
        return false;
      }

      // Device registratsiya (silent — xato bo'lsa hech narsa qilmaydi)
      await _registerDevice();

      return true;
    } on TimeoutException {
      lastError.value = 'Nexus serverga ulanish vaqti tugadi';
      return false;
    } catch (e) {
      lastError.value = 'Tarmoq xatosi: $e';
      return false;
    }
  }

  Future<bool> _refreshMe() async {
    if (_baseUrl == null || _token == null || _tenant == null) return false;
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/v1/auth/me'),
        headers: {
          'Authorization': 'Bearer $_token',
          'X-EigenGuard-Tenant': _tenant!,
        },
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return false;
      final user = NexusUser.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
      currentUser.value = user;
      await _storage.write(key: _kUserJson, value: jsonEncode(user.toJson()));
      return true;
    } catch (e) {
      debugPrint('[NexusAuth] /me err: $e');
      return false;
    }
  }

  Future<void> _registerDevice() async {
    if (_baseUrl == null || _token == null || _tenant == null) return;
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/api/v1/devices/register'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
              'X-EigenGuard-Tenant': _tenant!,
            },
            body: jsonEncode({
              'device_identifier': _deviceId,
              'platform': defaultTargetPlatform.name,
              'device_name': 'EigenGuard Mobile',
              'app_version': '1.0.0',
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[NexusAuth] register err: $e');
    }
  }

  Future<void> logout() async {
    // Server'ga logout chaqiruvi (best-effort)
    if (_baseUrl != null && _token != null && _tenant != null) {
      try {
        await http.post(
          Uri.parse('$_baseUrl/api/v1/auth/logout'),
          headers: {
            'Authorization': 'Bearer $_token',
            'X-EigenGuard-Tenant': _tenant!,
          },
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    _baseUrl = null;
    _tenant = null;
    _token = null;
    currentUser.value = null;
    await _storage.delete(key: _kBaseUrl);
    await _storage.delete(key: _kTenant);
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kEmail);
    await _storage.delete(key: _kUserJson);
    // Device ID saqlanib qoladi — keyingi login'da bir xil qurilma sifatida ko'rinadi
  }

  /// Helper: REST chaqiruvlar uchun standart headers.
  Map<String, String> authHeaders({String contentType = 'application/json'}) {
    final h = <String, String>{};
    if (contentType.isNotEmpty) h['Content-Type'] = contentType;
    if (_token != null) h['Authorization'] = 'Bearer $_token';
    if (_tenant != null) h['X-EigenGuard-Tenant'] = _tenant!;
    return h;
  }

  String? _extractError(String body, {String fallback = 'Xato'}) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] is String) return j['detail'] as String;
    } catch (_) {}
    return fallback;
  }
}
