import 'package:shared_preferences/shared_preferences.dart';

/// SettingsService — Ilovaning barcha sozlamalarini SharedPreferences da saqlaydi.
/// Singleton pattern. Ilovada bir marta `await SettingsService.init()` chaqiriladi.
class SettingsService {
  static SettingsService? _instance;
  late SharedPreferences _prefs;

  SettingsService._();

  /// Ilovani ishga tushirishda bir marta chaqiriladi
  static Future<SettingsService> init() async {
    if (_instance != null) return _instance!;
    final svc = SettingsService._();
    svc._prefs = await SharedPreferences.getInstance();
    _instance = svc;
    return svc;
  }

  /// Ilovaning istalgan joyidan olish (init() dan keyin)
  factory SettingsService() {
    assert(
        _instance != null, 'SettingsService.init() main() da chaqirilmagan!');
    return _instance!;
  }

  // ─────────────────────────────────────────
  // Xavf Chegaralari (Risk Thresholds)
  // ─────────────────────────────────────────

  double get warningThreshold => _prefs.getDouble('warning_threshold') ?? 30.0;
  double get highRiskThreshold =>
      _prefs.getDouble('high_risk_threshold') ?? 60.0;
  double get criticalThreshold =>
      _prefs.getDouble('critical_threshold') ?? 85.0;

  Future<void> setWarningThreshold(double v) =>
      _prefs.setDouble('warning_threshold', v);
  Future<void> setHighRiskThreshold(double v) =>
      _prefs.setDouble('high_risk_threshold', v);
  Future<void> setCriticalThreshold(double v) =>
      _prefs.setDouble('critical_threshold', v);

  // ─────────────────────────────────────────
  // Monitoring Parametrlari
  // ─────────────────────────────────────────

  int get sampleRate => _prefs.getInt('sample_rate') ?? 30;
  int get splinePoints => _prefs.getInt('spline_points') ?? 50;
  bool get autoAlert => _prefs.getBool('auto_alert') ?? false;
  bool get saveHistory => _prefs.getBool('save_history') ?? true;

  Future<void> setSampleRate(int v) => _prefs.setInt('sample_rate', v);
  Future<void> setSplinePoints(int v) => _prefs.setInt('spline_points', v);
  Future<void> setAutoAlert(bool v) => _prefs.setBool('auto_alert', v);
  Future<void> setSaveHistory(bool v) => _prefs.setBool('save_history', v);

  // ─────────────────────────────────────────
  // Qurilma Ma'lumotlari
  // ─────────────────────────────────────────

  String get deviceName => _prefs.getString('device_name') ?? 'Qurilma 1';
  String get location => _prefs.getString('location') ?? '';
  String get engineerName => _prefs.getString('engineer_name') ?? '';
  
  // ─────────────────────────────────────────
  // Sun'iy Intellekt (AI)
  // ─────────────────────────────────────────

  String get geminiApiKey => _prefs.getString('gemini_api_key') ?? '';
  Future<void> setGeminiApiKey(String v) => _prefs.setString('gemini_api_key', v);

  // ─────────────────────────────────────────
  // Sprint 16 — B2G ekotizimi (Demo Mode + MQTT + Nexus)
  // ─────────────────────────────────────────

  /// Demo Mode — sotuv demosida fusion qoidasini chetlab o'tadi.
  /// ON bo'lsa kamera-only alert ham `consensusCritical` triggeri sifatida ishlaydi.
  bool get demoMode => _prefs.getBool('demo_mode') ?? false;
  Future<void> setDemoMode(bool v) => _prefs.setBool('demo_mode', v);

  /// MQTT broker host (HiveMQ Cloud, EMQX, mosquitto, ...). Bo'sh — mock rejim.
  String get mqttBrokerHost => _prefs.getString('mqtt_broker_host') ?? '';
  Future<void> setMqttBrokerHost(String v) =>
      _prefs.setString('mqtt_broker_host', v);

  int get mqttBrokerPort => _prefs.getInt('mqtt_broker_port') ?? 1883;
  Future<void> setMqttBrokerPort(int v) =>
      _prefs.setInt('mqtt_broker_port', v);

  String get mqttUsername => _prefs.getString('mqtt_username') ?? '';
  Future<void> setMqttUsername(String v) =>
      _prefs.setString('mqtt_username', v);

  String get mqttPassword => _prefs.getString('mqtt_password') ?? '';
  Future<void> setMqttPassword(String v) =>
      _prefs.setString('mqtt_password', v);

  /// **Sprint 18 — Nexus base URL** (e.g. `https://demo.eigenguard.uz`).
  /// Auth, WS, measurements va boshqa endpointlar shu URL'dan keladi.
  String get nexusBaseUrl => _prefs.getString('nexus_base_url') ?? '';
  Future<void> setNexusBaseUrl(String v) =>
      _prefs.setString('nexus_base_url', v.replaceAll(RegExp(r'/+$'), ''));

  /// **Sprint 18 — Tenant subdomain** (e.g. `demo`).
  /// `X-EigenGuard-Tenant` header'iga qo'shiladi.
  String get nexusTenantSubdomain =>
      _prefs.getString('nexus_tenant_subdomain') ?? '';
  Future<void> setNexusTenantSubdomain(String v) =>
      _prefs.setString('nexus_tenant_subdomain', v);

  /// **DEPRECATED** (Sprint 16) — Sprint 18 dan keyin `nexusBaseUrl` ishlatiladi.
  /// Eski yozuvlar uchun saqlanadi, lekin yangi kodda chaqirilmaydi.
  String get nexusEndpoint => _prefs.getString('nexus_endpoint') ?? '';
  Future<void> setNexusEndpoint(String v) =>
      _prefs.setString('nexus_endpoint', v);

  /// **DEPRECATED** (Sprint 16) — Sprint 18 dan keyin `NexusAuthService` JWT'ni
  /// secure storage'da o'zi boshqaradi.
  String get nexusAuthToken => _prefs.getString('nexus_auth_token') ?? '';
  Future<void> setNexusAuthToken(String v) =>
      _prefs.setString('nexus_auth_token', v);

  Future<void> setDeviceName(String v) => _prefs.setString('device_name', v);
  Future<void> setLocation(String v) => _prefs.setString('location', v);
  Future<void> setEngineerName(String v) =>
      _prefs.setString('engineer_name', v);

  // ─────────────────────────────────────────
  // Sozlamalarni Reset
  // ─────────────────────────────────────────

  Future<void> resetToDefaults() async {
    await _prefs.clear();
  }

  // ─────────────────────────────────────────
  // Xavf Darajasini Hisoblash (Sozlamalarga mos)
  // ─────────────────────────────────────────

  String getRiskLevel(double riskPercent) {
    if (riskPercent < warningThreshold) return 'LOW';
    if (riskPercent < highRiskThreshold) return 'MEDIUM';
    if (riskPercent < criticalThreshold) return 'HIGH';
    return 'CRITICAL';
  }

  bool isCritical(double riskPercent) => riskPercent >= criticalThreshold;
  bool isHigh(double riskPercent) => riskPercent >= highRiskThreshold;
  bool isWarning(double riskPercent) => riskPercent >= warningThreshold;
}
