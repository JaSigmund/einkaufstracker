import 'dart:async';

import 'package:flutter/services.dart';

/// Schnellaktionen von ausserhalb der App: Widget auf dem Startbildschirm und langes Druecken auf das App-Symbol (ADR-041).
abstract class QuickActionSource {
  /// Aktion, mit der die App gestartet wurde (einmalig), sonst null.
  Future<String?> takeInitial();

  /// Aktionen, die bei laufender App ankommen.
  Stream<String> get incoming;
}

/// Android: eigener Kanal zu MainActivity.kt.
class AndroidQuickActionSource implements QuickActionSource {
  AndroidQuickActionSource() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'quickActionAvailable') {
        final action = await takeInitial();
        if (action != null) _controller.add(action);
      }
    });
  }

  static const _channel = MethodChannel('at.jakob.einkaufstracker/quick');
  final _controller = StreamController<String>.broadcast();

  @override
  Future<String?> takeInitial() async {
    try {
      return await _channel.invokeMethod<String>('takeQuickAction');
    } on MissingPluginException {
      return null; // Plattform ohne Widget (Web, Tests, Desktop)
    }
  }

  @override
  Stream<String> get incoming => _controller.stream;
}
