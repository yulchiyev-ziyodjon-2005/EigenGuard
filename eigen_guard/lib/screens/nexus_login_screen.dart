import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/nexus_auth_service.dart';
import '../services/nexus_ws_client.dart';
import '../services/nexus_command_handler.dart';
import '../services/settings_service.dart';

/// Sprint 18 — Nexus login UI.
/// Foydalanuvchi baseUrl + tenant + email + password ni kiritadi.
/// Muvaffaqiyatli login bo'lsa: JWT secure storage'ga yoziladi, Device
/// avtomatik ravishda registratsiya bo'ladi, WebSocket ulanadi.
class NexusLoginScreen extends StatefulWidget {
  const NexusLoginScreen({super.key});

  @override
  State<NexusLoginScreen> createState() => _NexusLoginScreenState();
}

class _NexusLoginScreenState extends State<NexusLoginScreen> {
  final _settings = SettingsService();
  final _auth = NexusAuthService();
  late TextEditingController _baseUrlCtrl;
  late TextEditingController _tenantCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _passwordCtrl;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl = TextEditingController(
      text: _settings.nexusBaseUrl.isNotEmpty
          ? _settings.nexusBaseUrl
          : 'http://10.0.2.2:8000', // Android emulator → host
    );
    _tenantCtrl = TextEditingController(
      text: _settings.nexusTenantSubdomain.isNotEmpty
          ? _settings.nexusTenantSubdomain
          : 'demo',
    );
    _emailCtrl = TextEditingController(text: 'engineer@demo.local');
    _passwordCtrl = TextEditingController(text: '');
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _tenantCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final base = _baseUrlCtrl.text.trim();
    final tenant = _tenantCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pwd = _passwordCtrl.text;

    final ok = await _auth.login(
      baseUrl: base,
      tenantSubdomain: tenant,
      email: email,
      password: pwd,
    );

    if (ok) {
      // Settings'da saqlab qo'yamiz (UI ko'rsatish uchun)
      await _settings.setNexusBaseUrl(base);
      await _settings.setNexusTenantSubdomain(tenant);
      // WebSocket'ni ulashni boshlash
      NexusWsClient().connect();
      NexusCommandHandler().start();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nexus\'ga login muvaffaqiyatli'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = _auth.lastError.value ?? 'Login muvaffaqiyatsiz';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: const Text(
          'NEXUS LOGIN',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        iconTheme: const IconThemeData(color: AppTheme.primary),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Icon(Icons.cloud, color: AppTheme.primary, size: 64),
              const SizedBox(height: 12),
              const Text(
                'Nexus Command Center',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'B2G Web Panel ulanish',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),
              _field(
                _baseUrlCtrl,
                label: 'Nexus URL',
                icon: Icons.link,
                hint: 'http://10.0.2.2:8000 yoki https://nexus.eigenguard.uz',
                keyboard: TextInputType.url,
              ),
              const SizedBox(height: 14),
              _field(
                _tenantCtrl,
                label: 'Tenant subdomain',
                icon: Icons.business,
                hint: 'demo',
              ),
              const SizedBox(height: 14),
              _field(
                _emailCtrl,
                label: 'Username yoki email',
                icon: Icons.email,
                keyboard: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              _field(
                _passwordCtrl,
                label: 'Parol',
                icon: Icons.lock,
                obscure: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.danger.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppTheme.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: AppTheme.danger, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              GestureDetector(
                onTap: _loading ? null : _submit,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _loading
                          ? [AppTheme.surfaceLight, AppTheme.surfaceLight]
                          : const [AppTheme.primary, AppTheme.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _loading
                        ? null
                        : [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_loading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(Icons.login,
                            color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _loading ? 'Kutilmoqda…' : 'KIRISH',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.15)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demo seed hisoblari:',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '• demo / engineer@demo.local / Engineer123!',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontFamily: 'monospace'),
                    ),
                    Text(
                      '• demo / admin@demo.local / DemoAdmin123!',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl, {
    required String label,
    required IconData icon,
    String? hint,
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboard,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        hintStyle: TextStyle(
            color: AppTheme.textMuted.withValues(alpha: 0.5), fontSize: 11),
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
}
