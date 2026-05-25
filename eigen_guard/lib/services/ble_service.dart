import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/external_sensor_reading.dart';

/// BLE ulanish holati — UI uchun
enum BleConnState {
  /// BT o'chiq yoki yo'q
  unavailable,

  /// Hech narsa qilinmayapti, ulanmagan
  idle,

  /// Skan qilinmoqda
  scanning,

  /// Tanlangan qurilmaga ulanmoqda
  connecting,

  /// Ulangan, characteristic kutmoqda
  connected,

  /// Notify subscribed — ma'lumot oqayapti
  streaming,
}

/// EigenGuard — Tashqi BLE sensor xizmati.
///
/// **Kontekst:** Telefon ichidagi IMU yaxshi, lekin sanoatda ko'pincha
/// kalibrlangan tashqi sensorlar ishlatiladi (Adafruit BNO055, Bosch BMI270,
/// TI SensorTag, DIY ESP32+MPU6050, ...). Bu xizmat shunday qurilmalardan
/// real-time o'qishlarni oladi va `LiveMetricsService` ga ulanadi.
///
/// **Foydalanish:**
/// 1. `startScan()` — atrofdagi BLE qurilmalarni 5 sek skan
/// 2. `connect(device)` — tanlangan qurilmaga ulanish
/// 3. `subscribe(char, decoder)` — notify characteristic'iga obuna bo'lish
class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  /// Joriy holat — UI ulanadi
  final ValueNotifier<BleConnState> state =
      ValueNotifier<BleConnState>(BleConnState.idle);

  /// Skan davrida topilgan qurilmalar
  final ValueNotifier<List<ScanResult>> scanResults =
      ValueNotifier<List<ScanResult>>(const []);

  /// Ulangan qurilma
  final ValueNotifier<BluetoothDevice?> connectedDevice =
      ValueNotifier<BluetoothDevice?>(null);

  /// Ulangan qurilma servislari (UI da characteristic tanlash uchun)
  final ValueNotifier<List<BluetoothService>> discoveredServices =
      ValueNotifier<List<BluetoothService>>(const []);

  /// So'nggi o'qilgan sensor reading — UI ga uzatiladi
  final ValueNotifier<ExternalSensorReading?> lastReading =
      ValueNotifier<ExternalSensorReading?>(null);

  /// Sensor history bufferi (1000 ta o'qish ~10 sek @ 100Hz)
  final List<ExternalSensorReading> historyBuffer = [];
  static const int _maxHistory = 1000;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifSub;
  BluetoothCharacteristic? _activeChar;
  BleProtocolDecoder decoder = BleProtocolDecoders.all.first;

  // ═════════════════════════════════════════════════════════════════════════
  // SKAN
  // ═════════════════════════════════════════════════════════════════════════
  Future<void> startScan({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      // BT yoqilganmi?
      if (await FlutterBluePlus.isSupported == false) {
        state.value = BleConnState.unavailable;
        return;
      }
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        state.value = BleConnState.unavailable;
        return;
      }

      scanResults.value = [];
      state.value = BleConnState.scanning;

      // Skan natijalarini tinglash
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        // Dublikatlarni olib tashlash (eng yaxshi RSSI ni saqlash)
        final Map<String, ScanResult> uniq = {};
        for (final r in results) {
          final id = r.device.remoteId.str;
          if (!uniq.containsKey(id) || uniq[id]!.rssi < r.rssi) {
            uniq[id] = r;
          }
        }
        final sorted = uniq.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        scanResults.value = sorted;
      });

      await FlutterBluePlus.startScan(timeout: timeout);

      // Timeout tugagach skanni to'xtatish
      await Future.delayed(timeout);
      await stopScan();
    } catch (e) {
      debugPrint('[BLE] skan xato: $e');
      state.value = BleConnState.idle;
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
    if (state.value == BleConnState.scanning) {
      state.value = connectedDevice.value != null
          ? BleConnState.connected
          : BleConnState.idle;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ULANISH
  // ═════════════════════════════════════════════════════════════════════════
  Future<bool> connect(BluetoothDevice device) async {
    try {
      await stopScan();
      state.value = BleConnState.connecting;

      // Ulanish holat tinglash
      _connSub?.cancel();
      _connSub = device.connectionState.listen((cs) async {
        if (cs == BluetoothConnectionState.disconnected) {
          await _cleanupActiveChar();
          discoveredServices.value = [];
          connectedDevice.value = null;
          state.value = BleConnState.idle;
        }
      });

      await device.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );

      connectedDevice.value = device;
      state.value = BleConnState.connected;

      // Servislarni topish
      final services = await device.discoverServices();
      discoveredServices.value = services;

      return true;
    } catch (e) {
      debugPrint('[BLE] ulanish xato: $e');
      state.value = BleConnState.idle;
      return false;
    }
  }

  Future<void> disconnect() async {
    final d = connectedDevice.value;
    if (d == null) return;
    try {
      await _cleanupActiveChar();
      await d.disconnect();
    } catch (e) {
      debugPrint('[BLE] uzilish xato: $e');
    }
    await _connSub?.cancel();
    _connSub = null;
    connectedDevice.value = null;
    discoveredServices.value = [];
    state.value = BleConnState.idle;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // OBUNA (subscribe)
  // ═════════════════════════════════════════════════════════════════════════
  /// Tanlangan characteristic'iga obuna bo'lish va decoder belgilash.
  /// Har keladigan notification → `decoder.decode(bytes)` → `lastReading` +
  /// `historyBuffer` yangilanadi.
  Future<bool> subscribe(
    BluetoothCharacteristic char,
    BleProtocolDecoder dec,
  ) async {
    try {
      await _cleanupActiveChar();
      decoder = dec;

      if (!char.properties.notify && !char.properties.indicate) {
        debugPrint('[BLE] tanlangan char notify qo\'llab-quvvatlamaydi');
        return false;
      }

      await char.setNotifyValue(true);

      _notifSub = char.lastValueStream.listen((bytes) {
        if (bytes.isEmpty) return;
        final reading = decoder.decode(Uint8List.fromList(bytes));
        lastReading.value = reading;
        historyBuffer.add(reading);
        if (historyBuffer.length > _maxHistory) {
          historyBuffer.removeAt(0);
        }
      });

      _activeChar = char;
      state.value = BleConnState.streaming;
      return true;
    } catch (e) {
      debugPrint('[BLE] subscribe xato: $e');
      return false;
    }
  }

  Future<void> _cleanupActiveChar() async {
    await _notifSub?.cancel();
    _notifSub = null;
    final c = _activeChar;
    if (c != null) {
      try {
        await c.setNotifyValue(false);
      } catch (_) {}
    }
    _activeChar = null;
    if (state.value == BleConnState.streaming) {
      state.value = BleConnState.connected;
    }
  }

  void clearHistory() {
    historyBuffer.clear();
    lastReading.value = null;
  }

  Future<void> dispose() async {
    await stopScan();
    await disconnect();
  }
}
