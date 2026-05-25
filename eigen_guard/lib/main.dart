// EigenGuard — Structural Health Monitoring System
// Responsive layout: Desktop (Sidebar) + Mobile (Bottom Navigation)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/digital_twin_screen.dart';
import 'screens/history_screen.dart';
import 'screens/monitoring_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'services/settings_service.dart';
import 'services/ai_assistant_service.dart';
import 'services/sensor_capability_service.dart';
import 'services/sensor_fusion_arbiter.dart';
import 'services/mqtt_ingest_service.dart';
import 'services/nexus_upload_service.dart';
import 'services/nexus_auth_service.dart';
import 'services/nexus_ws_client.dart';
import 'services/nexus_command_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sozlamalar xizmatini ishga tushirish
  await SettingsService.init();
  // Sprint 16 — Demo Mode + B2G uploader + real MQTT (agar broker sozlangan bo'lsa)
  final settings = SettingsService();
  SensorFusionArbiter().demoMode = settings.demoMode;
  if (settings.mqttBrokerHost.isNotEmpty) {
    // Real broker — fon (bloklamaydi); xato bo'lsa Dashboard mock'ga qaytadi
    // ignore: unawaited_futures
    MqttIngestService().connectReal(
      brokerHost: settings.mqttBrokerHost,
      port: settings.mqttBrokerPort,
      username: settings.mqttUsername.isEmpty ? null : settings.mqttUsername,
      password: settings.mqttPassword.isEmpty ? null : settings.mqttPassword,
    );
  }
  // Sprint 18 — Nexus auth bootstrap (saqlangan sessiyani tiklash)
  await NexusAuthService().bootstrap();
  // Command handler doim ishlaydi (WS dan kelgan commandlarni eshitadi)
  NexusCommandHandler().start();
  // Agar avval login bo'lgan bo'lsa — WebSocket'ni avtomatik ulash
  if (NexusAuthService().isAuthenticated) {
    NexusWsClient().connect();
  }
  // Nexus uploader — endpoint bo'sh bo'lsa o'z-o'zidan no-op rejimda qoladi
  NexusUploadService().start();
  // Qurilma sensorlarini probe qilish (fon — bloklamaydi)
  // ignore: unawaited_futures
  SensorCapabilityService().probe();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const EigenGuardApp());
}

class EigenGuardApp extends StatelessWidget {
  const EigenGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EigenGuard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigation(),
    );
  }
}

/// Responsive navigatsiya — ekran kengligiga qarab Sidebar yoki BottomNav
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  bool _sidebarExpanded = true;

  static const _navItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.monitor_heart_rounded, 'Monitoring'),
    _NavItem(Icons.history_rounded, 'Tarix'),
    _NavItem(Icons.view_in_ar_rounded, '3D Twin'),
    _NavItem(Icons.smart_toy_rounded, 'AI Consult'),
    _NavItem(Icons.settings_rounded, 'Sozlamalar'),
  ];

  late final AiAssistantService _aiService;

  @override
  void initState() {
    super.initState();
    _aiService = AiAssistantService();
  }

  List<Widget> get _screens => [
        const DashboardScreen(),
        MonitoringScreen(
          aiService: _aiService,
          onTabRequested: (index) => setState(() => _currentIndex = index),
        ),
        const HistoryScreen(),
        DigitalTwinScreen(
          onTabRequested: (index) => setState(() => _currentIndex = index),
        ),
        AiChatScreen(aiService: _aiService),
        const SettingsScreen(),
      ];

  /// Ekran kengligi > 700 bo'lsa desktop layout
  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width > 700;

  @override
  Widget build(BuildContext context) {
    return _isDesktop(context) ? _buildDesktopLayout() : _buildMobileLayout();
  }

  // ====================================================================
  // MOBILE LAYOUT — Bottom Navigation Bar
  // ====================================================================
  Widget _buildMobileLayout() {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(
              color: AppTheme.primary.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _navItems
                  .asMap()
                  .entries
                  .map((e) => _mobileNavItem(e.value, e.key))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileNavItem(_NavItem item, int index) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: isActive
            ? BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              color: isActive ? AppTheme.primary : AppTheme.textMuted,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                color: isActive ? AppTheme.primary : AppTheme.textMuted,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====================================================================
  // DESKTOP LAYOUT — Sidebar
  // ====================================================================
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _sidebarExpanded ? 220 : 72,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border(
                right: BorderSide(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                _buildSidebarHeader(),
                const Divider(color: AppTheme.surfaceLight, height: 1),
                const SizedBox(height: 8),
                ..._navItems.asMap().entries.map(
                      (e) => _buildSidebarItem(e.value, e.key),
                    ),
                const Spacer(),
                _buildEngineStatus(),
                const SizedBox(height: 12),
              ],
            ),
          ),
          // Content
          Expanded(
            child: IndexedStack(index: _currentIndex, children: _screens),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return InkWell(
      onTap: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.2),
                    AppTheme.secondary.withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.shield,
                color: AppTheme.primary,
                size: 20,
              ),
            ),
            if (_sidebarExpanded) ...[
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EigenGuard',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      'v0.1.0',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_left_rounded,
                color: AppTheme.textMuted,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(_NavItem item, int index) {
    final isActive = _currentIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => setState(() => _currentIndex = index),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: _sidebarExpanded ? 14 : 0,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isActive
                  ? Border.all(color: AppTheme.primary.withValues(alpha: 0.2))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: _sidebarExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  color: isActive ? AppTheme.primary : AppTheme.textMuted,
                  size: 20,
                ),
                if (_sidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: isActive
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (isActive)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEngineStatus() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: EdgeInsets.all(_sidebarExpanded ? 12 : 8),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: _sidebarExpanded
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
              ),
            ),
            if (_sidebarExpanded) ...[
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'C++ Engine',
                      style: TextStyle(
                        color: AppTheme.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Online',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 9),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
