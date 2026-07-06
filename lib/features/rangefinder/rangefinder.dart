import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

enum RangefinderStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

extension RangefinderStatusLabel on RangefinderStatus {
  String get label {
    switch (this) {
      case RangefinderStatus.disconnected:
        return 'Не подключено';
      case RangefinderStatus.scanning:
        return 'Поиск устройств';
      case RangefinderStatus.connecting:
        return 'Подключение';
      case RangefinderStatus.connected:
        return 'Подключено';
      case RangefinderStatus.error:
        return 'Ошибка';
    }
  }
}

class RangefinderReading {
  RangefinderReading({
    required this.valueMm,
    required this.timestamp,
    required this.source,
  });

  final int valueMm;
  final DateTime timestamp;
  final String source;
}

class RangefinderDeviceCandidate {
  const RangefinderDeviceCandidate({
    required this.id,
    required this.name,
    required this.rssi,
    required this.hasKnownService,
    required this.serviceUuids,
  });

  final String id;
  final String name;
  final int rssi;
  final bool hasKnownService;
  final List<String> serviceUuids;

  String get label => name.isEmpty ? 'Без имени' : name;
}

abstract class RangefinderBackend {
  Stream<RangefinderStatus> get statusStream;
  Stream<RangefinderReading> get readingStream;
  Stream<String> get logStream;
  Stream<List<RangefinderDeviceCandidate>> get devicesStream;
  RangefinderStatus get status;
  String get backendLabel;

  Future<void> start();
  Future<void> stop();

  /// Force one shot reading. For BLE backends rare devices that don't push
  /// notifications could implement here. Default: do nothing — readings come
  /// from the device when the user fires the laser.
  Future<void> requestShot() async {}

  Future<void> connectToDevice(String id) async {}
}

/// Test/demo backend. It emits a random measurement only when the user
/// explicitly requests a test shot.
class MockRangefinderBackend implements RangefinderBackend {
  MockRangefinderBackend();

  final _statusController = StreamController<RangefinderStatus>.broadcast();
  final _readingController = StreamController<RangefinderReading>.broadcast();
  final _logController = StreamController<String>.broadcast();
  final _devicesController = StreamController<List<RangefinderDeviceCandidate>>.broadcast();
  final _random = Random();
  RangefinderStatus _status = RangefinderStatus.disconnected;

  @override
  Stream<RangefinderStatus> get statusStream => _statusController.stream;

  @override
  Stream<RangefinderReading> get readingStream => _readingController.stream;

  @override
  Stream<String> get logStream => _logController.stream;

  @override
  Stream<List<RangefinderDeviceCandidate>> get devicesStream => _devicesController.stream;

  @override
  RangefinderStatus get status => _status;

  @override
  String get backendLabel => 'Тестовый дальномер';

  void _setStatus(RangefinderStatus value) {
    _status = value;
    if (!_statusController.isClosed) _statusController.add(value);
  }

  void _log(String message) {
    if (!_logController.isClosed) _logController.add(message);
  }

  @override
  Future<void> start() async {
    _setStatus(RangefinderStatus.connecting);
    _log('Тестовый режим: запуск');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _setStatus(RangefinderStatus.connected);
    _log('Тестовый режим: готов. Случайный замер выдаётся только по кнопке.');
  }

  @override
  Future<void> stop() async {
    _setStatus(RangefinderStatus.disconnected);
    _log('Тестовый режим: остановлен');
  }

  @override
  Future<void> requestShot() async {
    if (_status != RangefinderStatus.connected) {
      await start();
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _emitRandom('shot');
  }

  void _emitRandom(String tag) {
    final mm = 500 + _random.nextInt(8500);
    final reading = RangefinderReading(
      valueMm: mm,
      timestamp: DateTime.now(),
      source: 'mock',
    );
    _log('Тест замер ($tag): $mm мм');
    if (!_readingController.isClosed) _readingController.add(reading);
  }

  @override
  Future<void> connectToDevice(String id) async {}

  Future<void> dispose() async {
    await _statusController.close();
    await _readingController.close();
    await _logController.close();
    await _devicesController.close();
  }
}

/// Real BLE backend for Bosch GLM 50‑27 CG.
/// Service UUID: 02a6c0d0-0451-4000-b000-fb3210111989
/// Characteristic: 02a6c0d1-0451-4000-b000-fb3210111989
/// Notifications start with 0xC0 0x55 0x10 0x06 and contain Float32 LE in
/// bytes 7..10 representing measurement in meters.
class BoschBleRangefinderBackend implements RangefinderBackend {
  BoschBleRangefinderBackend();

  static final fbp.Guid serviceUuid =
      fbp.Guid('02a6c0d0-0451-4000-b000-fb3210111989');
  static final fbp.Guid charUuid =
      fbp.Guid('02a6c0d1-0451-4000-b000-fb3210111989');
  static final fbp.Guid altServiceUuid =
      fbp.Guid('3ab10100-f831-4395-b29d-570977d5bf94');
  static const List<int> enableMeasurementCommand = [
    0xc0,
    0x55,
    0x02,
    0x01,
    0x00,
    0x1a,
  ];
  static const List<int> triggerMeasurementCommand = [
    0xc0,
    0x40,
    0x00,
    0xee,
  ];
  static const Map<int, String> mtStatus = {
    0: 'ok',
    1: 'communication timeout',
    3: 'checksum error',
    4: 'unknown command',
    5: 'invalid access level',
    8: 'hardware error',
    10: 'device not ready',
  };

  final _statusController = StreamController<RangefinderStatus>.broadcast();
  final _readingController = StreamController<RangefinderReading>.broadcast();
  final _logController = StreamController<String>.broadcast();
  final _devicesController = StreamController<List<RangefinderDeviceCandidate>>.broadcast();

  RangefinderStatus _status = RangefinderStatus.disconnected;
  StreamSubscription<List<fbp.ScanResult>>? _scanSub;
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSub;
  final List<StreamSubscription<List<int>>> _notifSubs = [];
  fbp.BluetoothDevice? _device;
  fbp.BluetoothCharacteristic? _measurementCharacteristic;
  bool _connectAttemptStarted = false;
  final Map<String, fbp.BluetoothDevice> _candidateDevices = {};
  final Map<String, RangefinderDeviceCandidate> _candidates = {};

  @override
  Stream<RangefinderStatus> get statusStream => _statusController.stream;

  @override
  Stream<RangefinderReading> get readingStream => _readingController.stream;

  @override
  Stream<String> get logStream => _logController.stream;

  @override
  Stream<List<RangefinderDeviceCandidate>> get devicesStream => _devicesController.stream;

  @override
  RangefinderStatus get status => _status;

  @override
  String get backendLabel => 'Bosch GLM 50‑27 CG';

  void _setStatus(RangefinderStatus value) {
    _status = value;
    if (!_statusController.isClosed) _statusController.add(value);
  }

  void _log(String message) {
    if (!_logController.isClosed) _logController.add(message);
    if (kDebugMode) debugPrint('[BoschBLE] $message');
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    final scan = statuses[Permission.bluetoothScan];
    final connect = statuses[Permission.bluetoothConnect];

    if ((scan == null || scan.isGranted) && (connect == null || connect.isGranted)) {
      return true;
    }
    _log('Bluetooth разрешения не выданы: scan=$scan, connect=$connect');
    return false;
  }

  @override
  Future<void> start() async {
    await stop();
    _candidateDevices.clear();
    _candidates.clear();
    _emitDevices();
    _setStatus(RangefinderStatus.scanning);
    _log('Запуск сканирования');
    _connectAttemptStarted = false;

    final granted = await _ensurePermissions();
    if (!granted) {
      _log('Нет разрешений на Bluetooth');
      _setStatus(RangefinderStatus.error);
      return;
    }

    if (await fbp.FlutterBluePlus.isSupported == false) {
      _log('Bluetooth не поддерживается на устройстве');
      _setStatus(RangefinderStatus.error);
      return;
    }

    try {
      await fbp.FlutterBluePlus.adapterState
          .firstWhere((state) => state == fbp.BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      _log('Bluetooth выключен');
      _setStatus(RangefinderStatus.error);
      return;
    }

    await _tryKnownDevices();
    if (_connectAttemptStarted) return;

    _scanSub = fbp.FlutterBluePlus.scanResults.listen(
      (results) {
        for (final result in results) {
          final hasService =
              result.advertisementData.serviceUuids.contains(serviceUuid) ||
                  result.advertisementData.serviceUuids.contains(altServiceUuid);
          final deviceName = _bestDeviceName(result.device, result);
          final looksLikeGlm = _looksLikeGlm(deviceName);
          _rememberCandidate(result, hasService: hasService);
          _log('BLE: ${deviceName.isEmpty ? 'без имени' : deviceName} (${result.device.remoteId}), '
              'rssi=${result.rssi}, service=${hasService ? 'да' : 'нет'}');
          if (hasService || looksLikeGlm) {
            _log('Найден подходящий дальномер: $deviceName (${result.device.remoteId})');
            _connectAttemptStarted = true;
            unawaited(_connectTo(result.device));
            return;
          }
        }
      },
      onError: (Object error) {
        _log('Ошибка сканирования: $error');
        _setStatus(RangefinderStatus.error);
      },
    );

    try {
      await fbp.FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidScanMode: fbp.AndroidScanMode.lowLatency,
        androidUsesFineLocation: true,
      );
      if (!_connectAttemptStarted && _device == null) {
        _log('Дальномер не найден. Проверьте, что на GLM включён Bluetooth и он не подключён к другому приложению.');
        _setStatus(RangefinderStatus.error);
      }
    } catch (error) {
      _log('Не удалось запустить сканирование: $error');
      _setStatus(RangefinderStatus.error);
    }
  }

  void _rememberCandidate(fbp.ScanResult result, {required bool hasService}) {
    final id = result.device.remoteId.toString();
    final serviceUuids = result.advertisementData.serviceUuids
        .map((uuid) => uuid.str)
        .toList(growable: false);
    _candidateDevices[id] = result.device;
    _candidates[id] = RangefinderDeviceCandidate(
      id: id,
      name: _bestDeviceName(result.device, result),
      rssi: result.rssi,
      hasKnownService: hasService,
      serviceUuids: serviceUuids,
    );
    _emitDevices();
  }

  void _emitDevices() {
    final list = _candidates.values.toList()
      ..sort((a, b) {
        if (a.hasKnownService != b.hasKnownService) {
          return a.hasKnownService ? -1 : 1;
        }
        return b.rssi.compareTo(a.rssi);
      });
    if (!_devicesController.isClosed) _devicesController.add(list);
  }

  @override
  Future<void> connectToDevice(String id) async {
    final device = _candidateDevices[id];
    if (device == null) {
      _log('Устройство $id уже не найдено в списке сканирования');
      _setStatus(RangefinderStatus.error);
      return;
    }
    _connectAttemptStarted = true;
    await _connectTo(device, allowAnyService: true);
  }

  Future<void> _tryKnownDevices() async {
    try {
      final bonded = await fbp.FlutterBluePlus.bondedDevices;
      for (final device in bonded) {
        final name = _bestDeviceName(device);
        if (name.isNotEmpty) _log('Сопряжённое устройство: $name (${device.remoteId})');
        if (_looksLikeGlm(name)) {
          _log('Пробуем подключиться к сопряжённому дальномеру: $name');
          _connectAttemptStarted = true;
          unawaited(_connectTo(device));
          return;
        }
      }
    } catch (error) {
      _log('Не удалось прочитать сопряжённые устройства: $error');
    }

    try {
      final connected = await fbp.FlutterBluePlus.systemDevices([serviceUuid]);
      for (final device in connected) {
        final name = _bestDeviceName(device);
        if (name.isNotEmpty) _log('Системно подключено: $name (${device.remoteId})');
        if (_looksLikeGlm(name)) {
          _log('Пробуем подключиться к уже подключённому дальномеру: $name');
          _connectAttemptStarted = true;
          unawaited(_connectTo(device));
          return;
        }
      }
    } catch (error) {
      _log('Не удалось прочитать системно подключённые устройства: $error');
    }
  }

  bool _looksLikeGlm(String name) {
    final normalized = name.toLowerCase();
    return normalized.startsWith('glm') ||
        normalized.contains('glm') ||
        normalized.contains('bosch') ||
        normalized.contains('laser');
  }

  String _bestDeviceName(fbp.BluetoothDevice device, [fbp.ScanResult? result]) {
    final advName = result?.advertisementData.advName ?? '';
    if (advName.trim().isNotEmpty) return advName.trim();
    if (device.platformName.trim().isNotEmpty) return device.platformName.trim();
    if (device.advName.trim().isNotEmpty) return device.advName.trim();
    return '';
  }

  Future<void> _connectTo(
    fbp.BluetoothDevice device, {
    bool allowAnyService = false,
  }) async {
    if (_device != null && _device!.remoteId != device.remoteId) return;
    _device = device;
    try {
      await fbp.FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;

    _setStatus(RangefinderStatus.connecting);
    _log('Подключение к ${_bestDeviceName(device).isEmpty ? device.remoteId.toString() : _bestDeviceName(device)}');

    _connectionSub = device.connectionState.listen((state) {
      _log('Состояние соединения: $state');
      if (state == fbp.BluetoothConnectionState.disconnected) {
        _setStatus(RangefinderStatus.disconnected);
      }
    });

    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 12));
    } catch (error) {
      _log('Ошибка подключения: $error');
      _setStatus(RangefinderStatus.error);
      _device = null;
      return;
    }

    try {
      final services = await device.discoverServices();
      _log('Найдено BLE-сервисов: ${services.length}');
      _logServices(services);
      final targetServices = services
          .where((service) => service.uuid == serviceUuid || service.uuid == altServiceUuid)
          .toList();
      if (targetServices.isEmpty) {
        if (allowAnyService) {
          _log('Bosch-сервис не найден, пробуем работать со всеми BLE-сервисами вручную');
          targetServices.addAll(services);
        } else {
        final ids = services.map((s) => s.uuid.str).join(', ');
        throw StateError('GLM-сервис не найден на устройстве. Сервисы: $ids');
        }
      }

      await _subscribeToMeasurementNotifications(targetServices);
      _measurementCharacteristic = _findWritableCharacteristic(targetServices);
      final characteristic = _measurementCharacteristic;
      if (characteristic == null) {
        throw StateError('Не найдена характеристика для отправки команд');
      }

      try {
        await characteristic.write(enableMeasurementCommand,
            withoutResponse: false);
        _log('Команда активации измерений отправлена');
      } catch (error) {
        _log('Не удалось включить поток измерений: $error (продолжаем слушать)');
      }

      _setStatus(RangefinderStatus.connected);
      _log('Готово. Делайте замер кнопкой на дальномере.');
    } catch (error) {
      _log('Ошибка инициализации сервисов: $error');
      _setStatus(RangefinderStatus.error);
      try {
        await device.disconnect();
      } catch (_) {}
      _device = null;
      _connectAttemptStarted = false;
    }
  }

  void _logServices(List<fbp.BluetoothService> services) {
    for (final service in services) {
      _log('Сервис ${service.uuid.str}');
      for (final characteristic in service.characteristics) {
        final properties = characteristic.properties;
        _log('  Хар. ${characteristic.uuid.str} '
            'read=${properties.read} write=${properties.write} '
            'writeNoResp=${properties.writeWithoutResponse} '
            'notify=${properties.notify} indicate=${properties.indicate}');
      }
    }
  }

  Future<void> _subscribeToMeasurementNotifications(
    List<fbp.BluetoothService> services,
  ) async {
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        final properties = characteristic.properties;
        if (!properties.notify && !properties.indicate) continue;
        try {
          await characteristic.setNotifyValue(true);
          final source = characteristic.uuid.str;
          final sub = characteristic.onValueReceived.listen(
            (data) => _handleData(data, source: source),
          );
          _notifSubs.add(sub);
          _log('Подписка на ${characteristic.uuid.str}');
        } catch (error) {
          _log('Не удалось подписаться на ${characteristic.uuid.str}: $error');
        }
      }
    }
    if (_notifSubs.isEmpty) {
      _log('Нет notify/indicate характеристик для замеров');
    }
  }

  fbp.BluetoothCharacteristic? _findWritableCharacteristic(
    List<fbp.BluetoothService> services,
  ) {
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == charUuid && characteristic.properties.write) {
          return characteristic;
        }
      }
    }
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        final properties = characteristic.properties;
        if (properties.write || properties.writeWithoutResponse) {
          return characteristic;
        }
      }
    }
    return null;
  }

  void _handleData(List<int> data, {required String source}) {
    if (data.isEmpty) return;
    final mtValueMm = _tryParseMtMeasurement(data);
    if (mtValueMm != null) {
      _emitMeasurement(mtValueMm, source: 'bosch_mt');
      return;
    }
    if (data.length < 11) {
      final status = mtStatus[data[0]];
      _log('Короткий ответ ${source.substring(0, 8)} (${data.length} б): ${_hex(data)}'
          '${status == null ? '' : ' - $status'}');
      return;
    }
    if (data[0] != 0xc0 || data[1] != 0x55) {
      _log('Пакет с другой сигнатурой ${source.substring(0, 8)} '
          '(${data.length} б): ${_hex(data)}');
      return;
    }
    if (data[2] != 0x10 || data[3] != 0x06) {
      return;
    }
    final bytes = Uint8List.fromList(data.sublist(7, 11));
    final meters =
        ByteData.sublistView(bytes).getFloat32(0, Endian.little);
    if (meters.isNaN || meters.isInfinite || meters <= 0) {
      _log('Невалидное значение от устройства: $meters');
      return;
    }
    _emitMeasurement((meters * 1000).round(), source: 'bosch_ble');
  }

  int? _tryParseMtMeasurement(List<int> data) {
    // MT receive frame: [status][length][payload...][checksum].
    // A direct measurement response returns 4 payload bytes as uint32 LE
    // in 0.05 mm units.
    if (data.length != 7 || data[0] != 0x00 || data[1] != 0x04) {
      return null;
    }
    final raw = ByteData.sublistView(
      Uint8List.fromList(data.sublist(2, 6)),
    ).getUint32(0, Endian.little);
    final mm = (raw * 0.05).round();
    if (mm <= 0 || mm > 100000) {
      _log('MT-значение вне диапазона: raw=$raw, mm=$mm, packet=${_hex(data)}');
      return null;
    }
    return mm;
  }

  void _emitMeasurement(int mm, {required String source}) {
    _log('Замер: $mm мм');
    if (!_readingController.isClosed) {
      _readingController.add(
        RangefinderReading(
          valueMm: mm,
          timestamp: DateTime.now(),
          source: source,
        ),
      );
    }
  }

  @override
  Future<void> stop() async {
    try {
      await fbp.FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
    _connectAttemptStarted = false;
    for (final sub in _notifSubs) {
      await sub.cancel();
    }
    _notifSubs.clear();
    _measurementCharacteristic = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    _setStatus(RangefinderStatus.disconnected);
  }

  @override
  Future<void> requestShot() async {
    final characteristic = _measurementCharacteristic;
    if (_status != RangefinderStatus.connected || characteristic == null) {
      _log('Нельзя отправить команду измерения: дальномер не готов');
      return;
    }

    try {
      await characteristic.write(enableMeasurementCommand, withoutResponse: false);
      _log('Sync-режим перед выстрелом активирован');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await characteristic.write(triggerMeasurementCommand, withoutResponse: false);
      _log('Команда выстрела отправлена');
    } catch (error) {
      _log('Команда выстрела с подтверждением не прошла: $error');
      try {
        await characteristic.write(triggerMeasurementCommand, withoutResponse: true);
        _log('Команда выстрела отправлена без подтверждения');
      } catch (fallbackError) {
        _log('Не удалось отправить команду выстрела: $fallbackError');
      }
    }
  }

  String _hex(Iterable<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  Future<void> dispose() async {
    await stop();
    await _statusController.close();
    await _readingController.close();
    await _logController.close();
    await _devicesController.close();
  }
}

/// Top level controller used by the UI. Switches between mock and BLE
/// backends on demand and exposes the latest measurement.
class RangefinderController extends ChangeNotifier {
  RangefinderController();

  RangefinderBackend? _backend;
  bool _testMode = false;
  RangefinderStatus _status = RangefinderStatus.disconnected;
  RangefinderReading? _lastReading;
  final List<RangefinderReading> _history = [];
  final List<RangefinderDeviceCandidate> _devices = [];
  final List<String> _log = [];
  StreamSubscription<RangefinderStatus>? _statusSub;
  StreamSubscription<RangefinderReading>? _readingSub;
  StreamSubscription<String>? _logSub;
  StreamSubscription<List<RangefinderDeviceCandidate>>? _devicesSub;
  final _readingsController = StreamController<RangefinderReading>.broadcast();

  bool get testMode => _testMode;
  RangefinderStatus get status => _status;
  RangefinderReading? get lastReading => _lastReading;
  List<RangefinderReading> get history => List.unmodifiable(_history);
  List<RangefinderDeviceCandidate> get devices => List.unmodifiable(_devices);
  List<String> get log => List.unmodifiable(_log);
  Stream<RangefinderReading> get readings => _readingsController.stream;
  String get currentBackendLabel =>
      _backend?.backendLabel ?? (_testMode ? 'Тестовый дальномер' : 'Bosch GLM 50‑27 CG');

  Future<void> setTestMode(bool enabled) async {
    if (_testMode == enabled && _backend != null) return;
    _testMode = enabled;
    await disconnect();
    notifyListeners();
  }

  void _attach(RangefinderBackend backend) {
    _backend = backend;
    _statusSub = backend.statusStream.listen((status) {
      _status = status;
      notifyListeners();
    });
    _readingSub = backend.readingStream.listen((reading) {
      _lastReading = reading;
      _history.insert(0, reading);
      if (_history.length > 30) _history.removeRange(30, _history.length);
      notifyListeners();
      if (!_readingsController.isClosed) {
        _readingsController.add(reading);
      }
    });
    _logSub = backend.logStream.listen((message) {
      final stamped = '${_formatTime(DateTime.now())}  $message';
      _log.insert(0, stamped);
      if (_log.length > 100) _log.removeRange(100, _log.length);
      notifyListeners();
    });
    _devicesSub = backend.devicesStream.listen((devices) {
      _devices
        ..clear()
        ..addAll(devices);
      notifyListeners();
    });
  }

  Future<void> _detach() async {
    await _statusSub?.cancel();
    await _readingSub?.cancel();
    await _logSub?.cancel();
    await _devicesSub?.cancel();
    _statusSub = null;
    _readingSub = null;
    _logSub = null;
    _devicesSub = null;
    final backend = _backend;
    _backend = null;
    if (backend is BoschBleRangefinderBackend) {
      await backend.dispose();
    } else if (backend is MockRangefinderBackend) {
      await backend.dispose();
    }
  }

  /// If Bluetooth is off, [onBluetoothOff] is called first. Return true to
  /// request system Bluetooth enablement, false to abort.
  Future<bool> ensureBluetoothReady({
    Future<bool> Function()? onBluetoothOff,
  }) async {
    if (_testMode) return true;
    if (await fbp.FlutterBluePlus.isSupported == false) return false;

    var state = await fbp.FlutterBluePlus.adapterState.first;
    if (state == fbp.BluetoothAdapterState.on) return true;

    final agreed = onBluetoothOff == null ? false : await onBluetoothOff();
    if (!agreed) return false;

    try {
      await fbp.FlutterBluePlus.turnOn();
    } catch (_) {}

    try {
      await fbp.FlutterBluePlus.adapterState
          .firstWhere((item) => item == fbp.BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 15));
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> connect({Future<bool> Function()? onBluetoothOff}) async {
    await disconnect();
    if (!_testMode) {
      final ready = await ensureBluetoothReady(onBluetoothOff: onBluetoothOff);
      if (!ready) {
        _status = RangefinderStatus.error;
        _log.insert(0, '${_formatTime(DateTime.now())}  Bluetooth не включён');
        notifyListeners();
        return;
      }
    }
    final backend = _testMode
        ? MockRangefinderBackend()
        : BoschBleRangefinderBackend();
    _attach(backend);
    notifyListeners();
    await backend.start();
  }

  Future<void> connectToDevice(
    String id, {
    Future<bool> Function()? onBluetoothOff,
  }) async {
    if (_backend == null || _testMode) {
      await connect(onBluetoothOff: onBluetoothOff);
    }
    await _backend?.connectToDevice(id);
  }

  Future<void> disconnect() async {
    final backend = _backend;
    if (backend != null) {
      await backend.stop();
    }
    await _detach();
    _status = RangefinderStatus.disconnected;
    notifyListeners();
  }

  Future<void> requestMeasurement({Future<bool> Function()? onBluetoothOff}) async {
    if (_backend == null || _status == RangefinderStatus.disconnected) {
      await connect(onBluetoothOff: onBluetoothOff);
    }
    await _backend?.requestShot();
  }

  /// Wait for the next measurement that arrives within [timeout].
  /// In test mode triggers a synthetic shot immediately.
  Future<RangefinderReading?> captureNext({
    Duration timeout = const Duration(seconds: 30),
    bool requestShot = true,
    Future<bool> Function()? onBluetoothOff,
  }) async {
    final armedAt = DateTime.now();
    if (_backend == null || _status == RangefinderStatus.disconnected) {
      await connect(onBluetoothOff: onBluetoothOff);
    }
    if (_backend == null) return null;
    final backend = _backend!;
    final completer = Completer<RangefinderReading?>();
    late StreamSubscription<RangefinderReading> sub;
    sub = readings.listen((reading) {
      if (reading.timestamp.isBefore(armedAt)) return;
      if (!completer.isCompleted) completer.complete(reading);
    });
    Timer? timer;
    timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });
    if (requestShot) unawaited(backend.requestShot());
    final result = await completer.future;
    await sub.cancel();
    timer.cancel();
    return result;
  }

  String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  @override
  Future<void> dispose() async {
    await _detach();
    await _readingsController.close();
    super.dispose();
  }
}
