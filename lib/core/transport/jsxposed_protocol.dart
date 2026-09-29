import 'dart:convert';

const jsxposedProtocolVersion = '1.0';
const jsxposedWebSocketPort = 8765;

/// 协议方法名，设备侧与 PC 侧共用，避免两端拼写漂移
abstract final class JsxposedMethod {
  static const handshake = 'handshake';
  static const heartbeat = 'heartbeat';
  static const requestCancel = 'request.cancel';

  static const deviceGetInfo = 'device.get_info';
  static const deviceGetCapabilities = 'device.get_capabilities';
  static const deviceGetHealth = 'device.get_health';
  static const deviceSubscribeEvents = 'device.subscribe_events';

  static const projectList = 'project.list';

  static const scriptList = 'script.list';
  static const scriptRead = 'script.read';
  static const scriptWrite = 'script.write';
  static const scriptDelete = 'script.delete';
  static const scriptToggle = 'script.toggle';
}

/// 脚本来源，对应手机端 Frida 与 Xposed 两套脚本目录
abstract final class JsxposedScriptSource {
  static const frida = 'frida';
  static const xposed = 'xposed';

  static const values = {frida, xposed};

  static bool isValid(String value) => values.contains(value);
}

/// 统一错误码
abstract final class JsxposedErrorCode {
  static const invalidParams = 'INVALID_PARAMS';
  static const protocolVersionUnsupported = 'PROTOCOL_VERSION_UNSUPPORTED';
  static const capabilityUnavailable = 'CAPABILITY_UNAVAILABLE';
  static const scriptNotFound = 'SCRIPT_NOT_FOUND';
  static const internalError = 'INTERNAL_ERROR';
}

class JsxposedMessage {
  const JsxposedMessage({
    required this.type,
    this.id,
    this.version,
    this.method,
    this.event,
    this.deviceId,
    this.sessionId,
    this.params,
    this.result,
    this.error,
    this.sequence,
    this.meta,
  });

  final String type;
  final String? id;
  final String? version;
  final String? method;
  final String? event;
  final String? deviceId;
  final String? sessionId;
  final Map<String, dynamic>? params;
  final dynamic result;
  final JsxposedError? error;
  final int? sequence;
  final Map<String, dynamic>? meta;

  bool get isResponse => type == 'response';
  bool get isEvent => type == 'event';
  bool get isSuccess => isResponse && error == null;

  Map<String, dynamic> toJson() => {
    'type': type,
    if (id != null) 'id': id,
    if (version != null) 'version': version,
    if (method != null) 'method': method,
    if (event != null) 'event': event,
    if (deviceId != null) 'deviceId': deviceId,
    if (sessionId != null) 'sessionId': sessionId,
    if (params != null) 'params': params,
    if (result != null) 'result': result,
    if (error != null) 'error': error!.toJson(),
    if (sequence != null) 'sequence': sequence,
    if (meta != null) 'meta': meta,
  };

  String encode() => jsonEncode(toJson());

  factory JsxposedMessage.fromJson(Map<String, dynamic> json) {
    final error = json['error'];
    return JsxposedMessage(
      type: json['type'] as String? ?? 'unknown',
      id: json['id'] as String?,
      version: json['version'] as String?,
      method: json['method'] as String?,
      event: json['event'] as String?,
      deviceId: json['deviceId'] as String?,
      sessionId: json['sessionId'] as String?,
      params: (json['params'] as Map?)?.cast<String, dynamic>(),
      result: json['result'],
      error: error is Map
          ? JsxposedError.fromJson(error.cast<String, dynamic>())
          : null,
      sequence: (json['sequence'] as num?)?.toInt(),
      meta: (json['meta'] as Map?)?.cast<String, dynamic>(),
    );
  }

  factory JsxposedMessage.decode(String value) => JsxposedMessage.fromJson(
    (jsonDecode(value) as Map).cast<String, dynamic>(),
  );

  factory JsxposedMessage.request({
    required String id,
    required String method,
    String? deviceId,
    String? sessionId,
    Map<String, dynamic>? params,
    int timeoutMs = 15000,
  }) => JsxposedMessage(
    type: 'request',
    id: id,
    version: jsxposedProtocolVersion,
    method: method,
    deviceId: deviceId,
    sessionId: sessionId,
    params: params,
    meta: {'timeoutMs': timeoutMs},
  );

  factory JsxposedMessage.response({
    required String id,
    required bool ok,
    dynamic result,
    JsxposedError? error,
    Map<String, dynamic>? meta,
  }) => JsxposedMessage(
    type: 'response',
    id: id,
    version: jsxposedProtocolVersion,
    result: ok ? result : null,
    error: ok ? null : error,
    meta: meta,
  );

  factory JsxposedMessage.event({
    required String event,
    required dynamic payload,
    String? deviceId,
    String? sessionId,
    int? sequence,
  }) => JsxposedMessage(
    type: 'event',
    version: jsxposedProtocolVersion,
    event: event,
    deviceId: deviceId,
    sessionId: sessionId,
    result: payload,
    sequence: sequence,
  );
}

class JsxposedError {
  const JsxposedError({
    required this.code,
    required this.message,
    this.details,
    this.retryable = false,
  });

  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final bool retryable;

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (details != null) 'details': details,
    'retryable': retryable,
  };

  factory JsxposedError.fromJson(Map<String, dynamic> json) => JsxposedError(
    code: json['code'] as String? ?? 'INTERNAL_ERROR',
    message: json['message'] as String? ?? 'Unknown error',
    details: (json['details'] as Map?)?.cast<String, dynamic>(),
    retryable: json['retryable'] as bool? ?? false,
  );
}

String newJsxposedRequestId() => 'req_${DateTime.now().microsecondsSinceEpoch}';
