import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// PC 端与手机端的连接状态
enum DesktopConnectionStatus { disconnected, connecting, connected }

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
  });

  final DesktopConnectionStatus status;
  final String address;
  final String? error;
  final List<DesktopAdbDevice> adbDevices;
  final String? selectedAdbSerial;

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
  }) {
    return DesktopConnectionState(
      status: status ?? this.status,
      address: address ?? this.address,
      error: clearError ? null : (error ?? this.error),
      adbDevices: adbDevices ?? this.adbDevices,
      selectedAdbSerial: clearSelectedAdbSerial
          ? null
          : (selectedAdbSerial ?? this.selectedAdbSerial),
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
  String? _adbForwardSerial;

  @override
  DesktopConnectionState build() {
    ref.onDispose(_close);
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
    if (state.isConnecting || state.isConnected) return;
    state = state.copyWith(selectedAdbSerial: serial, clearError: true);
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
      final socket = await WebSocket.connect(address);
      _socket = socket;

      socket.listen(
        (_) {},
        onDone: _handleClosed,
        onError: (Object error) => _handleError(error.toString()),
        cancelOnError: true,
      );

      state = state.copyWith(
        status: DesktopConnectionStatus.connected,
        clearError: true,
      );
    } catch (error) {
      _handleError(error.toString());
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _close();
    state = state.copyWith(status: DesktopConnectionStatus.disconnected);
  }

  void _handleClosed() {
    _socket = null;
    state = state.copyWith(status: DesktopConnectionStatus.disconnected);
  }

  void _handleError(String message) {
    _socket = null;
    state = state.copyWith(
      status: DesktopConnectionStatus.disconnected,
      error: message,
    );
  }

  Future<void> _close() async {
    final socket = _socket;
    _socket = null;
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
