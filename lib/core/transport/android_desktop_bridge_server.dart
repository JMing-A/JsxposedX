import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:JsxposedX/core/transport/jsxposed_protocol.dart';
import 'package:JsxposedX/generated/status_management.g.dart';

class AndroidDesktopBridgeServer {
  AndroidDesktopBridgeServer._();

  static final instance = AndroidDesktopBridgeServer._();

  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  final StatusManagementNative _statusManagement = StatusManagementNative();
  Map<String, dynamic>? _deviceInfo;

  /// 当前已连接的 PC 客户端数量，供手机端界面展示电脑连接状态
  final ValueNotifier<int> clientCount = ValueNotifier<int>(0);

  bool get isRunning => _server != null;
  bool get hasClient => clientCount.value > 0;

  void _syncClientCount() => clientCount.value = _clients.length;

  Future<void> start() async {
    if (kIsWeb || !Platform.isAndroid || isRunning) return;
    _deviceInfo = await _loadDeviceInfo();
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        jsxposedWebSocketPort,
        shared: true,
      );
      _server = server;
      unawaited(_serve(server));
    } catch (error, stackTrace) {
      debugPrint('Failed to start desktop bridge: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> stop() async {
    final clients = _clients.toList();
    _clients.clear();
    _syncClientCount();
    for (final client in clients) {
      await client.close();
    }
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.upgradeRequired
          ..write('WebSocket upgrade required');
        await request.response.close();
        continue;
      }
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _clients.add(socket);
        _syncClientCount();
        socket.listen(
          (data) => _handleMessage(socket, data),
          onDone: () {
            _clients.remove(socket);
            _syncClientCount();
          },
          onError: (_) {
            _clients.remove(socket);
            _syncClientCount();
          },
          cancelOnError: true,
        );
      } catch (error) {
        debugPrint('Desktop bridge upgrade failed: $error');
      }
    }
  }

  Future<void> _handleMessage(WebSocket socket, dynamic data) async {
    JsxposedMessage request;
    try {
      request = JsxposedMessage.decode(data.toString());
    } catch (error) {
      socket.add(
        JsxposedMessage.response(
          id: 'unknown',
          ok: false,
          error: JsxposedError(
            code: 'SCRIPT_INVALID',
            message: 'Invalid protocol message: $error',
          ),
        ).encode(),
      );
      return;
    }

    if (request.type != 'request' || request.id == null) return;
    final startedAt = DateTime.now();
    try {
      final result = await _route(request);
      socket.add(
        JsxposedMessage.response(
          id: request.id!,
          ok: true,
          result: result,
          meta: {
            'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
          },
        ).encode(),
      );
    } on _ProtocolException catch (error) {
      socket.add(
        JsxposedMessage.response(
          id: request.id!,
          ok: false,
          error: JsxposedError(code: error.code, message: error.message),
        ).encode(),
      );
    } catch (error) {
      socket.add(
        JsxposedMessage.response(
          id: request.id!,
          ok: false,
          error: JsxposedError(
            code: 'INTERNAL_ERROR',
            message: error.toString(),
          ),
        ).encode(),
      );
    }
  }

  Future<Map<String, dynamic>> _route(JsxposedMessage request) async {
    switch (request.method) {
      case 'handshake':
        final requestedVersion = request.params?['protocolVersion'];
        if (requestedVersion != jsxposedProtocolVersion) {
          throw const _ProtocolException(
            'PROTOCOL_VERSION_UNSUPPORTED',
            'Unsupported protocol version',
          );
        }
        return {
          'protocolVersion': jsxposedProtocolVersion,
          'server': 'JsxposedX Android',
          'deviceId': _deviceInfo?['deviceId'],
        };
      case 'heartbeat':
        return {'timestamp': DateTime.now().toUtc().toIso8601String()};
      case 'device.get_info':
        return Map<String, dynamic>.from(_deviceInfo ?? const {});
      case 'device.get_capabilities':
        return _loadCapabilities();
      case 'device.get_health':
        return {
          'status': 'ready',
          'connectedClients': _clients.length,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        };
      case 'device.subscribe_events':
        return {'subscribed': true};
      case 'request.cancel':
        return {'cancelled': request.params?['requestId']};
      default:
        throw _ProtocolException(
          'CAPABILITY_UNAVAILABLE',
          'Unsupported method: ${request.method}',
        );
    }
  }

  Future<Map<String, dynamic>> _loadCapabilities() async {
    final results = await Future.wait<dynamic>([
      _readCapability<bool>(_statusManagement.isHook, false),
      _readCapability<bool>(_statusManagement.isRoot, false),
      _readCapability<FridaStatusData>(
        _statusManagement.isFrida,
        FridaStatusData(status: false, type: -1),
      ),
    ]);
    final isHook = results[0] as bool;
    final isRoot = results[1] as bool;
    final frida = results[2] as FridaStatusData;
    return buildDesktopBridgeCapabilities(
      deviceId: _deviceInfo?['deviceId'] as String?,
      isHook: isHook,
      isRoot: isRoot,
      isFridaReady: frida.status,
      fridaType: frida.type,
    );
  }

  Future<T> _readCapability<T>(Future<T> Function() read, T fallback) async {
    try {
      return await read();
    } catch (error) {
      debugPrint('Desktop bridge capability check failed: $error');
      return fallback;
    }
  }

  Future<Map<String, dynamic>> _loadDeviceInfo() async {
    final info = await DeviceInfoPlugin().androidInfo;
    return {
      'deviceId': info.id,
      'platform': 'android',
      'androidApi': info.version.sdkInt,
      'androidVersion': info.version.release,
      'abi': info.supportedAbis.isEmpty ? 'unknown' : info.supportedAbis.first,
      'model': info.model,
      'manufacturer': info.manufacturer,
    };
  }
}

@visibleForTesting
Map<String, dynamic> buildDesktopBridgeCapabilities({
  required String? deviceId,
  required bool isHook,
  required bool isRoot,
  required bool isFridaReady,
  required int fridaType,
}) {
  return {
    'deviceId': deviceId,
    'protocolVersion': jsxposedProtocolVersion,
    'platform': 'android',
    'capabilities': {
      'xposed': {'available': isHook, 'framework': isHook ? 'LSPosed' : null},
      'frida': {
        'available': isFridaReady,
        'installed': fridaType >= 0,
        'mode': fridaType == 1 ? 'zygisk' : null,
        'state': switch (fridaType) {
          1 => 'ready',
          0 => 'installed',
          _ => 'unavailable',
        },
      },
      'root': isRoot,
      'memory': isRoot,
      'shell': isRoot,
      'screenshot': true,
    },
  };
}

class _ProtocolException implements Exception {
  const _ProtocolException(this.code, this.message);

  final String code;
  final String message;
}
