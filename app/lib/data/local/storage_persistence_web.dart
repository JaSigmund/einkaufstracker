import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Ruft `navigator.storage.persist()` auf (Web Storage API). Best effort: schlaegt der Aufruf fehl oder
/// lehnt der Browser ab, bleibt die App trotzdem voll funktionsfaehig, nur eben ohne die zusaetzliche
/// Zusicherung gegen automatisches Loeschen bei Speicherdruck.
Future<void> webRequestPersistentStorage() async {
  try {
    await web.window.navigator.storage.persist().toDart;
  } catch (_) {
    // Manche Browser kennen die API nicht oder lehnen sie ab (z.B. ohne vorherige Nutzerinteraktion) --
    // kein kritischer Pfad, die App funktioniert in jedem Fall weiter.
  }
}
