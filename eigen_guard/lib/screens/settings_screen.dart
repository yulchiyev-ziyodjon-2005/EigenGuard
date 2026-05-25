import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/settings_service.dart';
import '../services/sensor_fusion_arbiter.dart';
import '../services/mqtt_ingest_service.dart';
import '../services/nexus_upload_service.dart';
import '../services/nexus_auth_service.dart';
import '../services/nexus_ws_client.dart';
import '../services/nexus_command_handler.dart';
import 'nexus_login_screen.dart';

/// Sozlamalar ekrani — SettingsService orqali barcha sozlamalar avtomatik saqlanadi
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();

  // Local state (SettingsService dan o'qiladi)
  late double _warningThreshold;
  late double _highRiskThreshold;
  late double _criticalThreshold;
  late int _sampleRate;
  late int _splinePoints;
  late bool _autoAlert;
  late bool _saveHistory;
  late TextEditingController _deviceNameCtrl;
  late TextEditingController _locationCtrl;
  late TextEditingController _engineerCtrl;
  late TextEditingController _geminiKeyCtrl;

  // Sprint 16 — B2G
  late bool _demoMode;
  late TextEditingController _mqttHostCtrl;
  late TextEditingController _mqttPortCtrl;
  late TextEditingController _mqttUserCtrl;
  late TextEditingController _mqttPassCtrl;
  late TextEditingController _nexusEndpointCtrl;
  late TextEditingController _nexusTokenCtrl;

  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _warningThreshold = _settings.warningThreshold;
    _highRiskThreshold = _settings.highRiskThreshold;
    _criticalThreshold = _settings.criticalThreshold;
    _sampleRate = _settings.sampleRate;
    _splinePoints = _settings.splinePoints;
    _autoAlert = _settings.autoAlert;
    _saveHistory = _settings.saveHistory;
    _deviceNameCtrl = TextEditingController(text: _settings.deviceName);
    _locationCtrl = TextEditingController(text: _settings.location);
    _engineerCtrl = TextEditingController(text: _settings.engineerName);
    _geminiKeyCtrl = TextEditingController(text: _settings.geminiApiKey);
    // Sprint 16 — B2G
    _demoMode = _settings.demoMode;
    _mqttHostCtrl = TextEditingController(text: _settings.mqttBrokerHost);
    _mqttPortCtrl =
        TextEditingController(text: _settings.mqttBrokerPort.toString());
    _mqttUserCtrl = TextEditingController(text: _settings.mqttUsername);
    _mqttPassCtrl = TextEditingController(text: _settings.mqttPassword);
    _nexusEndpointCtrl =
        TextEditingController(text: _settings.nexusEndpoint);
    _nexusTokenCtrl = TextEditingController(text: _settings.nexusAuthToken);
  }

  @override
  void dispose() {
    _deviceNameCtrl.dispose();
    _locationCtrl.dispose();
    _engineerCtrl.dispose();
    _geminiKeyCtrl.dispose();
    _mqttHostCtrl.dispose();
    _mqttPortCtrl.dispose();
    _mqttUserCtrl.dispose();
    _mqttPassCtrl.dispose();
    _nexusEndpointCtrl.dispose();
    _nexusTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _settings.setWarningThreshold(_warningThreshold);
    await _settings.setHighRiskThreshold(_highRiskThreshold);
    await _settings.setCriticalThreshold(_criticalThreshold);
    await _settings.setSampleRate(_sampleRate);
    await _settings.setSplinePoints(_splinePoints);
    await _settings.setAutoAlert(_autoAlert);
    await _settings.setSaveHistory(_saveHistory);
    await _settings.setDeviceName(_deviceNameCtrl.text.trim());
    await _settings.setLocation(_locationCtrl.text.trim());
    await _settings.setEngineerName(_engineerCtrl.text.trim());
    await _settings.setGeminiApiKey(_geminiKeyCtrl.text.trim());
    // Sprint 16 — B2G persist + immediate effect
    await _settings.setDemoMode(_demoMode);
    SensorFusionArbiter().demoMode = _demoMode;
    final mqttHost = _mqttHostCtrl.text.trim();
    final mqttPort =
        int.tryParse(_mqttPortCtrl.text.trim()) ?? _settings.mqttBrokerPort;
    final mqttUser = _mqttUserCtrl.text.trim();
    final mqttPass = _mqttPassCtrl.text;
    await _settings.setMqttBrokerHost(mqttHost);
    await _settings.setMqttBrokerPort(mqttPort);
    await _settings.setMqttUsername(mqttUser);
    await _settings.setMqttPassword(mqttPass);
    await _settings.setNexusEndpoint(_nexusEndpointCtrl.text.trim());
    await _settings.setNexusAuthToken(_nexusTokenCtrl.text.trim());
    // Reconfigure live services
    NexusUploadService().restart();
    if (mqttHost.isNotEmpty) {
      // ignore: unawaited_futures
      MqttIngestService().connectReal(
        brokerHost: mqttHost,
        port: mqttPort,
        username: mqttUser.isEmpty ? null : mqttUser,
        password: mqttPass.isEmpty ? null : mqttPass,
      );
    } else {
      MqttIngestService().stopAll();
    }
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Sozlamalar saqlandi'),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saved = false);
      });
    }
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Standartga qaytarish',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Barcha sozlamalar standart qiymatga qaytarilsin?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BEKOR',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('QAYTARISH',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _settings.resetToDefaults();
      if (mounted) {
        setState(() {
          _warningThreshold = 30.0;
          _highRiskThreshold = 60.0;
          _criticalThreshold = 85.0;
          _sampleRate = 30;
          _splinePoints = 50;
          _autoAlert = false;
          _saveHistory = true;
          _deviceNameCtrl.text = 'Qurilma 1';
          _locationCtrl.text = '';
          _engineerCtrl.text = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(),
            const SizedBox(height: 16),

            // Qurilma ma'lumotlari
            _buildSectionHeader('Qurilma Ma\'lumotlari', Icons.devices_rounded),
            const SizedBox(height: 8),
            _buildDeviceCard(),
            const SizedBox(height: 20),

            // Xavf chegaralari
            _buildSectionHeader(
                'Xavf Chegaralari', Icons.warning_amber_rounded),
            const SizedBox(height: 8),
            _buildThresholdCard(),
            const SizedBox(height: 20),

            // Sun'iy Intellekt (AI)
            _buildSectionHeader('Sun\'iy Intellekt (AI)', Icons.smart_toy_rounded),
            const SizedBox(height: 8),
            _buildAiCard(),
            const SizedBox(height: 20),

            // Sprint 16 — B2G ekotizimi (Demo + MQTT + Nexus)
            _buildSectionHeader('B2G Ekotizimi', Icons.hub_rounded),
            const SizedBox(height: 8),
            _buildB2GCard(),
            const SizedBox(height: 20),

            // Monitoring sozlamalari
            _buildSectionHeader('Monitoring', Icons.monitor_heart),
            const SizedBox(height: 8),
            _buildMonitoringCard(),
            const SizedBox(height: 20),

            // Tizim haqida
            _buildSectionHeader('Tizim Haqida', Icons.info_outline),
            const SizedBox(height: 8),
            _buildAboutCard(),
            const SizedBox(height: 20),

            // Saqlash tugmasi
            _buildSaveButton(),
            const SizedBox(height: 12),
            _buildResetButton(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.settings_rounded, color: AppTheme.primary, size: 22),
        const SizedBox(width: 10),
        const Text(
          'SOZLAMALAR',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        if (_saved)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.check, color: AppTheme.success, size: 14),
                SizedBox(width: 4),
                Text('Saqlandi',
                    style: TextStyle(color: AppTheme.success, fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildDeviceCard() {
    return Container(
      decoration: AppTheme.glassCard,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTextField(
              'Qurilma nomi', _deviceNameCtrl, Icons.precision_manufacturing),
          const SizedBox(height: 10),
          _buildTextField(
              'Joylashuv', _locationCtrl, Icons.location_on_rounded),
          const SizedBox(height: 10),
          _buildTextField('Muhandis ismi', _engineerCtrl, Icons.person_rounded),
        ],
      ),
    );
  }

  /// Sprint 16 — B2G ekotizimi sozlamalari kartochkasi.
  /// Demo Mode toggle + MQTT broker + Nexus endpoint + qo'lda sync tugmasi.
  Widget _buildB2GCard() {
    return Container(
      decoration: AppTheme.glassCard,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Demo Mode — Sales/Field uchun KRITIK toggle
          _buildSwitchRow(
            label: 'Demo Mode',
            subtitle:
                'ON: kamera-only ham KRITIK alert beradi (ESP32 talab qilinmaydi). '
                'Sotuv demosi va dala muhandisi standalone rejimi uchun.',
            value: _demoMode,
            onChanged: (v) {
              setState(() => _demoMode = v);
              // Effekt darhol — saqlash kutilmaydi
              SensorFusionArbiter().demoMode = v;
            },
          ),
          const Divider(color: AppTheme.surfaceLight),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'MQTT BROKER (ESP32 Edge node)',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          _buildTextField('Broker hosti (bo\'sh — mock rejim)',
              _mqttHostCtrl, Icons.router_rounded),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField('Port', _mqttPortCtrl, Icons.numbers),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: _buildTextField(
                    'Username (ixt.)', _mqttUserCtrl, Icons.person_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _mqttPassCtrl,
            obscureText: true,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Password (ixt.)',
              labelStyle:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              prefixIcon: const Icon(Icons.lock_outline,
                  color: AppTheme.primary, size: 18),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.surfaceLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
              filled: true,
              fillColor: AppTheme.background.withValues(alpha: 0.5),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<MqttConnectionState>(
            valueListenable: MqttIngestService().state,
            builder: (context, mqttState, _) {
              return _statusPill(MqttIngestService().statusLabel,
                  _mqttStateColor(mqttState));
            },
          ),
          const Divider(color: AppTheme.surfaceLight, height: 24),
          _buildNexusAuthSection(),
          const SizedBox(height: 10),
          // Nexus status + Sync now tugmasi
          ValueListenableBuilder<NexusSyncState>(
            valueListenable: NexusUploadService().state,
            builder: (context, nState, _) {
              return ValueListenableBuilder<int>(
                valueListenable: NexusUploadService().pendingCount,
                builder: (context, pending, _) {
                  return Row(
                    children: [
                      Expanded(
                        child: _statusPill(
                          '${NexusUploadService().statusLabel} · $pending ta pending',
                          _nexusStateColor(nState),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => NexusUploadService().syncNow(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    AppTheme.primary.withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sync,
                                  color: AppTheme.primary, size: 14),
                              SizedBox(width: 6),
                              Text(
                                'SYNC NOW',
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<String?>(
            valueListenable: NexusUploadService().lastError,
            builder: (context, err, _) {
              if (err == null || err.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '⚠ $err',
                  style: const TextStyle(
                      color: AppTheme.danger,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Sprint 18 — Nexus auth & WebSocket holati
  Widget _buildNexusAuthSection() {
    return ValueListenableBuilder<NexusUser?>(
      valueListenable: NexusAuthService().currentUser,
      builder: (context, user, _) {
        if (user == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'NEXUS WEB PANEL (Auth talab qiladi)',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Text(
                'Nexus Command Center bilan ulanish uchun login qiling. '
                'JWT token avtomatik secure storage\'da saqlanadi.',
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NexusLoginScreen()),
                  );
                  if (result == true && mounted) setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.login, color: AppTheme.primary, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'NEXUS\'GA LOGIN',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'NEXUS WEB PANEL (Faol)',
                style: TextStyle(
                  color: AppTheme.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppTheme.success.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Tenant', user.tenantName),
                  _kv('Subdomain', user.tenantSubdomain),
                  _kv('Email', user.email),
                  if (user.fullName != null) _kv('FIO', user.fullName!),
                  _kv('Roli',
                      user.isSuperadmin ? 'Superadmin' : (user.isAdmin ? 'Admin' : 'Xodim')),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // WebSocket holati
            ValueListenableBuilder<NexusWsState>(
              valueListenable: NexusWsClient().state,
              builder: (context, ws, _) {
                Color c;
                String label;
                switch (ws) {
                  case NexusWsState.connected:
                    c = AppTheme.success;
                    label = 'WS · CONNECTED';
                    break;
                  case NexusWsState.connecting:
                    c = AppTheme.warning;
                    label = 'WS · CONNECTING';
                    break;
                  case NexusWsState.error:
                    c = AppTheme.danger;
                    label = 'WS · ERROR';
                    break;
                  case NexusWsState.disconnected:
                    c = AppTheme.textMuted;
                    label = 'WS · DISCONNECTED';
                }
                return Row(
                  children: [
                    Expanded(child: _statusPill('$label  ·  ${user.tenantSubdomain}', c)),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () {
                        if (ws == NexusWsState.connected ||
                            ws == NexusWsState.connecting) {
                          NexusWsClient().disconnect();
                        } else {
                          NexusWsClient().connect();
                          NexusCommandHandler().start();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          ws == NexusWsState.connected
                              ? Icons.power_settings_new
                              : Icons.play_arrow,
                          color: c,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                NexusWsClient().disconnect();
                NexusCommandHandler().stop();
                await NexusAuthService().logout();
                if (mounted) setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, color: AppTheme.danger, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'LOGOUT (JWT o\'chiriladi)',
                      style: TextStyle(
                        color: AppTheme.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(k,
                style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.5)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Color _mqttStateColor(MqttConnectionState s) {
    switch (s) {
      case MqttConnectionState.connected:
        return AppTheme.success;
      case MqttConnectionState.mockedStreaming:
        return AppTheme.warning;
      case MqttConnectionState.connecting:
        return AppTheme.primary;
      case MqttConnectionState.error:
        return AppTheme.danger;
      case MqttConnectionState.disconnected:
        return AppTheme.textMuted;
    }
  }

  Color _nexusStateColor(NexusSyncState s) {
    switch (s) {
      case NexusSyncState.success:
        return AppTheme.success;
      case NexusSyncState.syncing:
        return AppTheme.primary;
      case NexusSyncState.failed:
        return AppTheme.danger;
      case NexusSyncState.disabled:
      case NexusSyncState.idle:
        return AppTheme.textMuted;
    }
  }

  Widget _buildAiCard() {
    return Container(
      decoration: AppTheme.glassCard,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _geminiKeyCtrl,
            obscureText: true,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Gemini API Kaliti',
              labelStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              prefixIcon: Icon(Icons.key, color: AppTheme.primary, size: 20),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.surfaceLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.surfaceLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primary),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'API kaliti qat\'iy xavfsiz holda mahalliy xotirada saqlanadi. '
            'AI funksiyalaridan foydalanish uchun majburiy.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
      String label, TextEditingController ctrl, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        prefixIcon: Icon(icon, color: AppTheme.primary, size: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.surfaceLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
        filled: true,
        fillColor: AppTheme.background.withValues(alpha: 0.5),
        isDense: true,
      ),
    );
  }

  Widget _buildThresholdCard() {
    return Container(
      decoration: AppTheme.glassCard,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildThresholdSlider(
            label: 'Ogohlantirish',
            value: _warningThreshold,
            color: AppTheme.warning,
            min: 10,
            max: _highRiskThreshold - 5,
            onChanged: (v) => setState(() => _warningThreshold = v),
          ),
          const Divider(color: AppTheme.surfaceLight),
          _buildThresholdSlider(
            label: 'Yuqori xavf',
            value: _highRiskThreshold,
            color: const Color(0xFFFF6B35),
            min: _warningThreshold + 5,
            max: _criticalThreshold - 5,
            onChanged: (v) => setState(() => _highRiskThreshold = v),
          ),
          const Divider(color: AppTheme.surfaceLight),
          _buildThresholdSlider(
            label: 'Kritik',
            value: _criticalThreshold,
            color: AppTheme.danger,
            min: _highRiskThreshold + 5,
            max: 99,
            onChanged: (v) => setState(() => _criticalThreshold = v),
          ),
        ],
      ),
    );
  }

  Widget _buildThresholdSlider({
    required String label,
    required double value,
    required Color color,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: color,
                inactiveTrackColor: AppTheme.surfaceLight,
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.1),
                trackHeight: 3,
              ),
              child: Slider(
                  value: value, min: min, max: max, onChanged: onChanged),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text('${value.toInt()}%',
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitoringCard() {
    return Container(
      decoration: AppTheme.glassCard,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildDropdownRow(
            label: 'Namuna tezligi (FPS)',
            value: _sampleRate,
            items: [15, 24, 30, 60],
            onChanged: (v) => setState(() => _sampleRate = v!),
          ),
          const Divider(color: AppTheme.surfaceLight),
          _buildDropdownRow(
            label: 'Splayn oynasi',
            value: _splinePoints,
            items: [20, 30, 50, 80, 100],
            onChanged: (v) => setState(() => _splinePoints = v!),
          ),
          const Divider(color: AppTheme.surfaceLight),
          _buildSwitchRow(
            label: 'Avtomatik ogohlantirish',
            subtitle: 'Kritik holatda bildirishnoma',
            value: _autoAlert,
            onChanged: (v) => setState(() => _autoAlert = v),
          ),
          const Divider(color: AppTheme.surfaceLight),
          _buildSwitchRow(
            label: 'Tarixni saqlash',
            subtitle: 'Har bir sessiyani saqlash',
            value: _saveHistory,
            onChanged: (v) => setState(() => _saveHistory = v),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow({
    required String label,
    required int value,
    required List<int> items,
    required ValueChanged<int?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(8)),
            child: DropdownButton<int>(
              value: value,
              items: items
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text('$e',
                            style: const TextStyle(
                                color: AppTheme.primary,
                                fontFamily: 'monospace',
                                fontSize: 13)),
                      ))
                  .toList(),
              onChanged: onChanged,
              dropdownColor: AppTheme.surface,
              underline: const SizedBox(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
            inactiveTrackColor: AppTheme.surfaceLight,
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      decoration: AppTheme.glassCard,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _aboutRow('Versiya', 'v1.0 (Production)'),
          _aboutRow('Matematik asos', '"Sonli usullar" — §6.1–6.4'),
          _aboutRow('C++ Engine', 'OpticalFlow + Kalman + FFT + Spline'),
          _aboutRow('Platforma', 'Flutter + Dart FFI + C++17'),
          _aboutRow('Vision AI', 'YOLO / ML Kit Object Detection'),
          _aboutRow('Akustika', 'MFCC Audio (PCM → FFT chastota)'),
          _aboutRow('IMU', 'Gyro + Accelerometer Sensor Fusion'),
          _aboutRow('Masofa', 'LiDAR Proxy (Monocular Depth)'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield, color: AppTheme.primary, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'EigenGuard v1.0 — Sanoat uskunalari sog\'ligini multimodal datchiklar bilan real vaqtda kuzatish tizimi',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          Flexible(
            child: Text(value,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: _save,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primary, AppTheme.primaryDark],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.save_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('SAQLASH',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return GestureDetector(
      onTap: _resetDefaults,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.refresh_rounded, color: AppTheme.danger, size: 16),
            SizedBox(width: 8),
            Text('STANDARTGA QAYTARISH',
                style: TextStyle(
                    color: AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}
