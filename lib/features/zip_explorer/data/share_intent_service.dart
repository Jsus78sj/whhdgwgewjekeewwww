import 'dart:async';
import 'package:flutter/services.dart';

class IncomingSharedZip {
  final String? path;
  final String? name;
  final int? size;
  final String? error;

  const IncomingSharedZip({
    this.path,
    this.name,
    this.size,
    this.error,
  });

  bool get hasFile => path != null && path!.isNotEmpty && error == null;

  factory IncomingSharedZip.fromMap(Map<dynamic, dynamic> map) {
    return IncomingSharedZip(
      path: map['path'] as String?,
      name: map['name'] as String?,
      size: (map['size'] as num?)?.toInt(),
      error: map['error'] as String?,
    );
  }
}

/// Bridges native Android Share Sheet (`ACTION_SEND` / `ACTION_VIEW`) intents
/// from `MainActivity.kt` into Flutter without third-party plugin conflicts.
class ShareIntentService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.githubnexus.app/share_intent');
  static const EventChannel _eventChannel =
      EventChannel('com.githubnexus.app/share_intent_stream');

  Future<IncomingSharedZip?> consumeInitialSharedZip() async {
    try {
      final result = await _methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('getInitialSharedZip');
      if (result == null) return null;
      return IncomingSharedZip.fromMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Stream<IncomingSharedZip> sharedZipStream() {
    try {
      return _eventChannel.receiveBroadcastStream().map((event) {
        if (event is Map) {
          return IncomingSharedZip.fromMap(event);
        }
        return const IncomingSharedZip(
          error: 'بيانات مشاركة غير صالحة من النظام.',
        );
      });
    } catch (_) {
      return const Stream<IncomingSharedZip>.empty();
    }
  }
}
