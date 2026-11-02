import 'dart:async';

import '../../data/share/quick_action_source.dart';

/// Fuehrt Schnellaktionen aus (ADR-041). "water" traegt sofort ein Glas ein, danach oeffnet jede Aktion die Seite Schnell eintragen:
/// dort sieht man den neuen Stand und kann den Eintrag zuruecknehmen. Ohne Anmeldung wartet die Aktion bis nach dem Login.
class QuickActionHandler {
  QuickActionHandler({required this.source, required this.isSignedIn, required this.takeWater, required this.open});

  static const water = 'water';

  final QuickActionSource source;
  final bool Function() isSignedIn;
  final Future<void> Function() takeWater;
  final void Function() open;

  StreamSubscription<String>? _sub;
  String? _pending;

  Future<void> start() async {
    _sub = source.incoming.listen(_handle);
    final initial = await source.takeInitial();
    if (initial != null) await _handle(initial);
  }

  /// Nach erfolgreicher Anmeldung aufrufen.
  Future<void> onSignedIn() async {
    final action = _pending;
    if (action == null) return;
    _pending = null;
    await _handle(action);
  }

  Future<void> _handle(String action) async {
    if (!isSignedIn()) {
      _pending = action;
      return;
    }
    try {
      if (action == water) await takeWater();
    } on Object {
      // Die Seite oeffnet trotzdem: dort laesst es sich von Hand nachholen, statt dass der Tipp spurlos verpufft
    }
    open();
  }

  void dispose() => _sub?.cancel();
}
