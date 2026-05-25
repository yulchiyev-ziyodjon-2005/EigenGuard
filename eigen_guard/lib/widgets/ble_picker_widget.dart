import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/app_theme.dart';
import '../models/external_sensor_reading.dart';
import '../services/ble_service.dart';

/// HUD da kompakt BLE indikatori — tap bo'lganda picker ochiladi
class BleStatusChip extends StatelessWidget {
  const BleStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final service = BleService();
    return ValueListenableBuilder<BleConnState>(
      valueListenable: service.state,
      builder: (context, st, _) {
        Color color;
        IconData icon;
        String label;
        switch (st) {
          case BleConnState.unavailable:
            color = AppTheme.textMuted;
            icon = Icons.bluetooth_disabled;
            label = 'BLE —';
            break;
          case BleConnState.idle:
            color = AppTheme.textSecondary;
            icon = Icons.bluetooth;
            label = 'BLE';
            break;
          case BleConnState.scanning:
            color = AppTheme.warning;
            icon = Icons.bluetooth_searching;
            label = 'SKAN';
            break;
          case BleConnState.connecting:
            color = AppTheme.warning;
            icon = Icons.bluetooth_searching;
            label = 'ULANISH';
            break;
          case BleConnState.connected:
            color = AppTheme.primary;
            icon = Icons.bluetooth_connected;
            label = 'BLE+';
            break;
          case BleConnState.streaming:
            color = AppTheme.success;
            icon = Icons.bluetooth_connected;
            label = 'STREAM';
            break;
        }
        return GestureDetector(
          onTap: () => showBlePickerSheet(context),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 12),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// BLE qurilmalarni topish va ulanish bottom sheet
void showBlePickerSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _BlePickerSheet(),
  );
}

class _BlePickerSheet extends StatefulWidget {
  const _BlePickerSheet();

  @override
  State<_BlePickerSheet> createState() => _BlePickerSheetState();
}

class _BlePickerSheetState extends State<_BlePickerSheet> {
  final _service = BleService();

  @override
  void initState() {
    super.initState();
    // Avtomatik skan boshlash (faqat hech narsa ulangan bo'lmasa)
    if (_service.connectedDevice.value == null) {
      _service.startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildHeader(),
              const SizedBox(height: 12),
              Expanded(
                child: ValueListenableBuilder<BluetoothDevice?>(
                  valueListenable: _service.connectedDevice,
                  builder: (context, device, _) {
                    if (device != null) {
                      return _buildConnectedView(device);
                    }
                    return _buildScanList();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ValueListenableBuilder<BleConnState>(
      valueListenable: _service.state,
      builder: (context, st, _) {
        return Row(
          children: [
            const Icon(Icons.sensors, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TASHQI BLE SENSORLAR',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    'External BLE accelerometer / strain gauge',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (st == BleConnState.scanning)
              const SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: AppTheme.warning),
              )
            else if (_service.connectedDevice.value == null)
              IconButton(
                onPressed: () => _service.startScan(),
                icon: const Icon(Icons.refresh, color: AppTheme.primary),
                tooltip: 'Qayta skan',
              )
            else
              IconButton(
                onPressed: () async {
                  await _service.disconnect();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.link_off, color: AppTheme.danger),
                tooltip: 'Uzish',
              ),
          ],
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // SKAN RO'YXATI
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildScanList() {
    return ValueListenableBuilder<List<ScanResult>>(
      valueListenable: _service.scanResults,
      builder: (context, results, _) {
        if (results.isEmpty) {
          return Center(
            child: ValueListenableBuilder<BleConnState>(
              valueListenable: _service.state,
              builder: (context, st, _) {
                if (st == BleConnState.unavailable) {
                  return const Text(
                    'Bluetooth o\'chiq yoki mavjud emas',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  );
                }
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bluetooth_searching,
                        color: AppTheme.textMuted.withValues(alpha: 0.4),
                        size: 56),
                    const SizedBox(height: 12),
                    const Text(
                      'Qurilmalar qidirilmoqda…',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          );
        }
        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) => _buildDeviceCard(results[i]),
        );
      },
    );
  }

  Widget _buildDeviceCard(ScanResult r) {
    final name = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : (r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : 'Noma\'lum qurilma');
    final rssiColor = r.rssi > -60
        ? AppTheme.success
        : (r.rssi > -80 ? AppTheme.warning : AppTheme.danger);

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final ok = await _service.connect(r.device);
          if (!mounted) return;
          if (!ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ulanib bo\'lmadi'),
                backgroundColor: AppTheme.danger,
              ),
            );
          } else {
            setState(() {});
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.bluetooth,
                  color: AppTheme.primary.withValues(alpha: 0.8), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text(
                      r.device.remoteId.str,
                      style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: rssiColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${r.rssi} dBm',
                  style: TextStyle(
                      color: rssiColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // ULANGAN QURILMA — characteristic tanlash + obuna
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildConnectedView(BluetoothDevice device) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.bluetooth_connected,
                  color: AppTheme.success, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.platformName.isNotEmpty
                          ? device.platformName
                          : 'Ulangan qurilma',
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800),
                    ),
                    Text(
                      device.remoteId.str,
                      style: const TextStyle(
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
        const SizedBox(height: 12),
        const Text('PROTOKOL TANLASH',
            style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        const SizedBox(height: 6),
        _buildDecoderSelector(),
        const SizedBox(height: 12),
        const Text('NOTIFY CHARACTERISTIC TANLANG',
            style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        const SizedBox(height: 6),
        Expanded(child: _buildCharList()),
        // So'nggi o'qish
        const SizedBox(height: 8),
        _buildLastReading(),
      ],
    );
  }

  Widget _buildDecoderSelector() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: BleProtocolDecoders.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final d = BleProtocolDecoders.all[i];
          final isActive = _service.decoder.runtimeType == d.runtimeType;
          return GestureDetector(
            onTap: () => setState(() => _service.decoder = d),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.primary.withValues(alpha: 0.2)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isActive
                        ? AppTheme.primary
                        : AppTheme.surfaceLight),
              ),
              child: Center(
                child: Text(
                  d.name,
                  style: TextStyle(
                    color: isActive
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCharList() {
    return ValueListenableBuilder<List<BluetoothService>>(
      valueListenable: _service.discoveredServices,
      builder: (context, services, _) {
        if (services.isEmpty) {
          return const Center(
            child: Text('Servislar yuklanmoqda…',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          );
        }
        final notifyChars = <BluetoothCharacteristic>[];
        for (final s in services) {
          for (final c in s.characteristics) {
            if (c.properties.notify || c.properties.indicate) {
              notifyChars.add(c);
            }
          }
        }
        if (notifyChars.isEmpty) {
          return const Center(
            child: Text(
              'Notify characteristic\'lari topilmadi',
              style: TextStyle(color: AppTheme.danger, fontSize: 11),
            ),
          );
        }
        return ListView.separated(
          itemCount: notifyChars.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (_, i) {
            final c = notifyChars[i];
            return Material(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok =
                      await _service.subscribe(c, _service.decoder);
                  if (!mounted) return;
                  if (!ok) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Obuna bo\'lib bo\'lmadi'),
                        backgroundColor: AppTheme.danger,
                      ),
                    );
                  } else {
                    setState(() {});
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      const Icon(Icons.podcasts,
                          color: AppTheme.primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.uuid.str,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLastReading() {
    return ValueListenableBuilder<ExternalSensorReading?>(
      valueListenable: _service.lastReading,
      builder: (context, r, _) {
        if (r == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SO\'NGGI O\'QISH',
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (r.hasAccel)
                Text(
                  'X=${r.accelX!.toStringAsFixed(2)}  Y=${r.accelY!.toStringAsFixed(2)}  Z=${r.accelZ!.toStringAsFixed(2)}  ‖${r.magnitude!.toStringAsFixed(2)}‖ m/s²',
                  style: const TextStyle(
                      color: AppTheme.success,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700),
                ),
              if (r.parseError != null)
                Text(r.parseError!,
                    style: const TextStyle(
                        color: AppTheme.danger, fontSize: 10)),
              const SizedBox(height: 4),
              Text(
                r.hexString,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 9,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        );
      },
    );
  }
}
