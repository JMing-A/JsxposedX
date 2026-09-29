import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:JsxposedX/core/transport/jsxposed_protocol.dart';

/// PC 端与手机端的连接状态
enum DesktopConnectionStatus { disconnected, connecting, connected }

@immutable
class DesktopDeviceInfo {
  const DesktopDeviceInfo({
    required this.deviceId,
    required this.platform,
    required this.androidApi,
    required this.abi,
    this.model,
    this.manufacturer,
  });

  final String deviceId;
  final String platform;
  final int androidApi;
  final String abi;
  final String? model;
  final String? manufacturer;

  factory DesktopDeviceInfo.fromJson(Map<String, dynamic> json) =>
      DesktopDeviceInfo(
        deviceId: json['deviceId'] as String? ?? '',
        platform: json['platform'] as String? ?? 'android',
        androidApi: (json['androidApi'] as num?)?.toInt() ?? 0,
        abi: json['abi'] as String? ?? 'unknown',
        model: json['model'] as String?,
        manufacturer: json['manufacturer'] as String?,
      );
}

@immutable
class DesktopDeviceCapabilities {
  const DesktopDeviceCapabilities({required this.values});

  final Map<String, dynamic> values;

  factory DesktopDeviceCapabilities.fromJson(Map<String, dynamic> json) =>
      DesktopDeviceCapabilities(values: Map<String, dynamic>.from(json));
}

@immutable
class DesktopAdbDevice {
  const DesktopAdbDevice({
    required this.serial,
    required this.state,
    this.model,
  });

  final String serial;
  final String state;
  final String? model;

  bool get isAuthorized => state == 'device';
  String get displayName => model == null ? serial : '$model ($serial)';
}

@immutable
class AdbCommandResult {
  const AdbCommandResult({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;

  bool get isSuccess => exitCode == 0;

  String get details {
    final lines = <String>['> $command', 'exit code: $exitCode'];
    if (stdout.isNotEmpty) lines.add('stdout:\n$stdout');
    if (stderr.isNotEmpty) lines.add('stderr:\n$stderr');
    return lines.join('\n');
  }
}

@immutable
class DesktopConnectionState {
  const DesktopConnectionState({
    this.status = DesktopConnectionStatus.disconnected,
    this.address = '',
    this.error,
    this.adbDevices = const [],
    this.selectedAdbSerial,
    this.deviceInfo,
    this.capabilities,
    this.lastResponse,
    List<JsxposedMessage>? events = const [],
  }) : _events = events;

  final DesktopConnectionStatus status;
  final String address;
  final String? error;
  final List<DesktopAdbDevice> adbDevices;
  final String? selectedAdbSerial;
  final DesktopDeviceInfo? deviceInfo;
  final DesktopDeviceCapabilities? capabilities;
  final JsxposedMessage? lastResponse;
  final List<JsxposedMessage>? _events;

  List<JsxposedMessage> get events => _events ?? const [];

  bool get isConnected => status == DesktopConnectionStatus.connected;
  bool get isConnecting => status == DesktopConnectionStatus.connecting;

  DesktopConnectionState copyWith({
    DesktopConnectionStatus? status,
    String? address,
    String? error,
    bool clearError = false,
    List<DesktopAdbDevice>? adbDevices,
    String? selectedAdbSerial,
    bool clearSelectedAdbSerial = false,
    DesktopDeviceInfo? deviceInfo,
    bool clearDeviceInfo = false,
    DesktopDeviceCapabilities? capabilities,
    bool clearCapabilities = false,
    JsxposedMessage? lastResponse,
    List<JsxposedMessage>? events,
  }) {
    return DesktopConnectionState(
      status: status ?? this.status,
      address: address ?? this.address,
      error: clearError ? null : (error ?? this.error),
      adbDevices: adbDevices ?? this.adbDevices,
      selectedAdbSerial: clearSelectedAdbSerial
          ? null
          : (selectedAdbSerial ?? this.selectedAdbSerial),
      deviceInfo: clearDeviceInfo ? null : (deviceInfo ?? this.deviceInfo),
      capabilities: clearCapabilities
          ? null
          : (capabilities ?? this.capabilities),
      lastResponse: lastResponse ?? this.lastResponse,
      events: events ?? this.events,
    );
  }
}

final desktopConnectionProvider =
    NotifierProvider<DesktopConnectionNotifier, DesktopConnectionState>(
      DesktopConnectionNotifier.new,
    );

/// 通过 WebSocket（HTTP 升级）与手机端保持即时双向连接
class DesktopConnectionNotifier extends Notifier<DesktopConnectionState> {
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _heartbeatTimer;
  String? _adbForwardSerial;
  final Map<String, Completer<JsxposedMessage>> _pendingRequests = {};

  Stream<JsxposedMessage> get events => _eventController.stream;
  final _eventController = StreamController<JsxposedMessage>.broadcast();

  @override
  DesktopConnectionState build() {
    ref.onDispose(() {
      unawaited(_close());
      unawaited(_eventController.close());
    });
    return const DesktopConnectionState();
  }

  Future<void> scanAdbDevices() async {
    try {
      final result = await Process.run('adb', ['devices', '-l']);
      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString().trim());
      }

      final devices = <DesktopAdbDevice>[];
      for (final line in result.stdout.toString().split('\n').skip(1)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2 || parts.first.isEmpty) continue;
        final modelPart = parts
            .where((part) => part.startsWith('model:'))
            .firstOrNull;
        devices.add(
          DesktopAdbDevice(
            serial: parts.first,
            state: parts[1],
            model: modelPart?.substring('model:'.length).replaceAll('_', ' '),
          ),
        );
      }

      final selected =
          state.selectedAdbSerial != null &&
              devices.any((device) => device.serial == state.selectedAdbSerial)
          ? state.selectedAdbSerial
          : null;
      state = state.copyWith(
        adbDevices: devices,
        selectedAdbSerial: selected,
        clearSelectedAdbSerial: selected == null,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(adbDevices: const [], error: error.toString());
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void selectAdbDevice(String serial) {
    if (state.isConnecting) return;
    state = state.copyWith(selectedAdbSerial: serial, clearError: true);
  }

  /// 切换到另一台设备：断开当前连接后重新连接目标设备
  Future<void> switchAdbDevice(String serial) async {
    if (state.isConnecting) return;
    if (state.selectedAdbSerial == serial && state.isConnected) return;
    await _close();
    state = state.copyWith(
      status: DesktopConnectionStatus.disconnected,
      selectedAdbSerial: serial,
      clearError: true,
      clearDeviceInfo: true,
      clearCapabilities: true,
    );
    await connectAdb();
  }

  Future<AdbCommandResult> pairAdb(String address, String pairingCode) async {
    final normalizedAddress = address.trim();
    final normalizedCode = pairingCode.trim();
    return _runAdbCommand(
      ['pair', normalizedAddress, normalizedCode],
      displayArguments: ['pair', normalizedAddress, '******'],
    );
  }

  Future<AdbCommandResult> connectAdbWireless(String address) async {
    final normalizedAddress = address.trim();
    final result = await _runAdbCommand(['connect', normalizedAddress]);
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    final commandReportedFailure =
        output.contains('failed') ||
        output.contains('unable') ||
        output.contains('cannot') ||
        output.contains('refused');
    final deviceConnected = state.adbDevices.any(
      (device) => device.serial == normalizedAddress && device.isAuthorized,
    );
    if (result.isSuccess && !commandReportedFailure && deviceConnected) {
      state = state.copyWith(
        selectedAdbSerial: normalizedAddress,
        clearError: true,
      );
      return result;
    }
    return AdbCommandResult(
      command: result.command,
      exitCode: result.exitCode == 0 ? 1 : result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr.isEmpty && !deviceConnected
          ? 'ADB command completed, but the device did not appear in adb devices -l.'
          : result.stderr,
    );
  }

  Future<AdbCommandResult> _runAdbCommand(
    List<String> arguments, {
    List<String>? displayArguments,
  }) async {
    final visibleArguments = displayArguments ?? arguments;
    final command = ['adb', ...visibleArguments].join(' ');
    try {
      final result = await Process.run('adb', arguments);
      final commandResult = AdbCommandResult(
        command: command,
        exitCode: result.exitCode,
        stdout: result.stdout.toString().trim(),
        stderr: result.stderr.toString().trim(),
      );
      if (commandResult.isSuccess) await scanAdbDevices();
      return commandResult;
    } on ProcessException catch (error) {
      return AdbCommandResult(
        command: command,
        exitCode: error.errorCode,
        stdout: '',
        stderr: error.toString(),
      );
    }
  }

  Future<void> connectAdb() async {
    final serial = state.selectedAdbSerial;
    if (serial == null) {
      _handleError('No ADB device selected');
      return;
    }

    if (!state.adbDevices.any(
      (device) => device.serial == serial && device.isAuthorized,
    )) {
      _handleError('Selected ADB device is not authorized');
      return;
    }

    try {
      final result = await Process.run('adb', [
        '-s',
        serial,
        'forward',
        'tcp:8765',
        'tcp:8765',
      ]);
      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString().trim());
      }
      _adbForwardSerial = serial;
      await connect('ws://127.0.0.1:8765');
    } catch (error) {
      _handleError(error.toString());
    }
  }

  /// 连接手机端，[address] 形如 ws://192.168.1.2:8765
  Future<void> connect(String address) async {
    if (state.isConnecting || state.isConnected) return;

    state = state.copyWith(
      status: DesktopConnectionStatus.connecting,
      address: address,
      clearError: true,
    );

    try {
      final socket = await WebSocket.connect(
        address,
      ).timeout(const Duration(seconds: 10));
      _socket = socket;
      _socketSubscription = socket.listen(
        _handleMessage,
        onDone: _handleClosed,
        onError: (Object error) => _handleError(error.toString()),
        cancelOnError: true,
      );

      final handshake = await request(
        'handshake',
        params: {
          'client': 'JsxposedX Desktop',
          'protocolVersion': jsxposedProtocolVersion,
        },
      );
      if (!handshake.isSuccess) {
        throw Exception(handshake.error?.message ?? 'Handshake failed');
      }
      final infoResponse = await request('device.get_info');
      final capabilitiesResponse = await request('device.get_capabilities');
      state = state.copyWith(
        status: DesktopConnectionStatus.connected,
        deviceInfo: _deviceInfoFromResponse(infoResponse),
        capabilities: _capabilitiesFromResponse(capabilitiesResponse),
        lastResponse: capabilitiesResponse,
        clearError: true,
      );
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        unawaited(_sendHeartbeat());
      });
    } catch (error) {
      await _close();
      _handleError(error.toString());
    }
  }

  Future<void> _sendHeartbeat() async {
    try {
      await request('heartbeat', timeout: const Duration(seconds: 5));
    } catch (error) {
      _handleError('Heartbeat failed: $error');
      await _close();
    }
  }

  Future<void> refreshDeviceContext() async {
    final infoResponse = await request('device.get_info');
    final capabilitiesResponse = await request('device.get_capabilities');
    state = state.copyWith(
      deviceInfo: _deviceInfoFromResponse(infoResponse),
      capabilities: _capabilitiesFromResponse(capabilitiesResponse),
      lastResponse: capabilitiesResponse,
    );
  }

  Future<JsxposedMessage> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('WebSocket is not connected');
    }
    final id = newJsxposedRequestId();
    final completer = Completer<JsxposedMessage>();
    _pendingRequests[id] = completer;
    socket.add(
      JsxposedMessage.request(
        id: id,
        method: method,
        deviceId: state.deviceInfo?.deviceId ?? state.selectedAdbSerial,
        params: params,
        timeoutMs: timeout.inMilliseconds,
      ).encode(),
    );
    try {
      final response = await completer.future.timeout(timeout);
      state = state.copyWith(lastResponse: response);
      return response;
    } on TimeoutException {
      _pendingRequests.remove(id);
      if (_socket != null) {
        _socket!.add(
          JsxposedMessage.request(
            id: newJsxposedRequestId(),
            method: 'request.cancel',
            params: {'requestId': id},
          ).encode(),
        );
      }
      throw TimeoutException('$method timed out', timeout);
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final message = JsxposedMessage.decode(data.toString());
      if (message.isResponse && message.id != null) {
        _pendingRequests.remove(message.id)?.complete(message);
        return;
      }
      if (message.isEvent) {
        _eventController.add(message);
        final updatedEvents = [...state.events, message];
        state = state.copyWith(
          events: updatedEvents.length > 100
              ? updatedEvents.sublist(updatedEvents.length - 100)
              : updatedEvents,
        );
      }
    } catch (error) {
      state = state.copyWith(error: 'Invalid protocol message: $error');
    }
  }

  DesktopDeviceInfo? _deviceInfoFromResponse(JsxposedMessage response) {
    final result = response.result;
    return response.isSuccess && result is Map
        ? DesktopDeviceInfo.fromJson(result.cast<String, dynamic>())
        : null;
  }

  DesktopDeviceCapabilities? _capabilitiesFromResponse(
    JsxposedMessage response,
  ) {
    final result = response.result;
    if (!response.isSuccess || result is! Map) return null;
    final json = result.cast<String, dynamic>();
    final capabilities = json['capabilities'];
    return capabilities is Map
        ? DesktopDeviceCapabilities.fromJson(
            capabilities.cast<String, dynamic>(),
          )
        : DesktopDeviceCapabilities.fromJson(json);
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _close();
    state = state.copyWith(status: DesktopConnectionStatus.disconnected);
  }

  void _handleClosed() {
    _socket = null;
    _heartbeatTimer?.cancel();
    _failPendingRequests('Connection closed');
    state = state.copyWith(
      status: DesktopConnectionStatus.disconnected,
      clearDeviceInfo: true,
      clearCapabilities: true,
    );
  }

  void _handleError(String message) {
    _socket = null;
    _heartbeatTimer?.cancel();
    _failPendingRequests(message);
    state = state.copyWith(
      status: DesktopConnectionStatus.disconnected,
      error: message,
      clearDeviceInfo: true,
      clearCapabilities: true,
    );
  }

  void _failPendingRequests(String message) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) completer.completeError(StateError(message));
    }
    _pendingRequests.clear();
  }

  Future<void> _close() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final subscription = _socketSubscription;
    _socketSubscription = null;
    await subscription?.cancel();
    final socket = _socket;
    _socket = null;
    _failPendingRequests('Connection closed');
    await socket?.close();
    final serial = _adbForwardSerial;
    _adbForwardSerial = null;
    if (serial != null) {
      await Process.run('adb', [
        '-s',
        serial,
        'forward',
        '--remove',
        'tcp:8765',
      ]);
    }
  }
}
