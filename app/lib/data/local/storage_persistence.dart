import 'storage_persistence_stub.dart' if (dart.library.js_interop) 'storage_persistence_web.dart';

/// Bittet den Browser, den App-Speicher als "persistent" einzustufen (Codereview-Fund 2026-10-01, iOS/
/// Safari-Strategie Option D): ohne das kann Safari insbesondere nicht synchronisierte lokale
/// Aenderungen (Outbox) bei Speicherdruck oder laengerer Inaktivitaet stillschweigend loeschen -- bei
/// einer offline-first App mit Outbox-Warteschlange waere das ein echter, unbemerkter Datenverlust.
/// Auf nativen Plattformen ein No-op (dort gibt es dieses Browser-Konzept nicht).
///
/// Hinweis: der Web-Zweig (`storage_persistence_web.dart`) nutzt `package:web`s direkte Web-API-Bindung;
/// `flutter analyze` prueft die Typen/Methodennamen dagegen (sauber), das tatsaechliche Verhalten im
/// Browser (gewaehrt Safari die Persistenz wirklich?) liess sich in dieser Umgebung aber nicht gegen
/// einen echten Browser verifizieren (gleiche akzeptierte Grenze wie bei ML Kit/`flutter_local_notifications`,
/// siehe ADR-Dokumentation) -- vor dem produktiven Einsatz einmal in Chrome/Safari pruefen.
Future<void> requestPersistentStorage() => webRequestPersistentStorage();
