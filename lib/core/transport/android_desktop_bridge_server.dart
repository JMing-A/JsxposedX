import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:JsxposedX/core/transport/jsxposed_protocol.dart';

class AndroidDesktopBridgeServer {
  AndroidDesktopBridgeServer._();

  static final instance = AndroidDesktopBridgeServer._();

  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  Map<String, dynamic>? _deviceInfo;

  bool get isRunning => _server != null;

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
        socket.listen(
          (data) => _handleMessage(socket, data),
          onDone: () => _clients.remove(socket),
          onError: (_) => _clients.remove(socket),
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
        return {
          'deviceId': _deviceInfo?['deviceId'],
          'protocolVersion': jsxposedProtocolVersion,
          'platform': 'android',
          'capabilities': {
            'xposed': {'available': false, 'framework': null},
            'frida': {'available': false, 'version': null, 'mode': null},
            'root': false,
            'memory': true,
            'shell': true,
            'screenshot': true,
          },
        };
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

class _ProtocolException implements Exception {
  const _ProtocolException(this.code, this.message);

  final String code;
  final String message;
}
