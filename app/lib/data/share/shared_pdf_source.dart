import 'dart:async';

import 'package:flutter/services.dart';

/// Quelle fuer PDFs, die andere Apps an diese App schicken ("Teilen" / "Oeffnen mit").
abstract class SharedPdfSource {
  /// PDF, mit dem die App gestartet wurde (einmalig), sonst null.
  Future<Uint8List?> takeInitial();

  /// PDFs, die bei laufender App ankommen.
  Stream<Uint8List> get incoming;
}

/// Android: Kanal zu MainActivity.kt.
class AndroidSharedPdfSource implements SharedPdfSource {
  AndroidSharedPdfSource() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedPdfAvailable') {
        final bytes = await takeInitial();
        if (bytes != null) _controller.add(bytes);
      }
    });
  }

  static const _channel = MethodChannel('at.jakob.einkaufstracker/share');
  final _controller = StreamController<Uint8List>.broadcast();

  @override
  Future<Uint8List?> takeInitial() async {
    try {
      return await _channel.invokeMethod<Uint8List>('takeSharedPdf');
    } on MissingPluginException {
      return null; // Plattform ohne Share-Unterstuetzung (Tests, Desktop)
    }
  }

  @override
  Stream<Uint8List> get incoming => _controller.stream;
}
