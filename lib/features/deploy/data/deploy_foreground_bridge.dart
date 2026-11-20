import 'dart:async';
import 'package:flutter/services.dart';

/// Dart bridge to Android's native `DeployForegroundService` (`MainActivity.kt`).
/// Safely degrades to no-op on non-Android platforms or unit tests.
class DeployForegroundBridge {
  static const MethodChannel _methodChannel =
      MethodChannel('com.githubnexus.app/deploy_service');
  static const EventChannel _eventChannel =
      EventChannel('com.githubnexus.app/deploy_service_events');

  Future<void> requestNotificationPermission() async {
    try {
      await _methodChannel.invokeMethod<void>('requestNotificationPermission');
    } on MissingPluginException {
      // No-op in tests / non-Android hosts
    } on PlatformException {
      // Ignore gracefully
    }
  }

  Future<void> start({
    required String title,
    required String subtitle,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('startForegroundDeploy', {
        'title': title,
        'subtitle': subtitle,
      });
    } on MissingPluginException {
    } on PlatformException {}
  }

  Future<void> updateProgress({
    required String title,
    required String subtitle,
    required int progress,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('updateForegroundProgress', {
        'title': title,
        'subtitle': subtitle,
        'progress': progress.clamp(0, 100),
      });
    } on MissingPluginException {
    } on PlatformException {}
  }

  Future<void> finish({
    required String title,
    required String subtitle,
    required bool success,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('finishForegroundDeploy', {
        'title': title,
        'subtitle': subtitle,
        'success': success,
      });
    } on MissingPluginException {
    } on PlatformException {}
  }

  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod<void>('stopForegroundDeploy');
    } on MissingPluginException {
    } on PlatformException {}
  }

  Stream<void> cancelRequestedStream() {
    try {
      return _eventChannel.receiveBroadcastStream().where((event) {
        return event is Map && event['event'] == 'cancel_requested';
      }).map((_) {});
    } catch (_) {
      return const Stream<void>.empty();
    }
  }
}
