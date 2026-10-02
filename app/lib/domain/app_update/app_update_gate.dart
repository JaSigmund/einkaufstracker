/// Ob die laufende App-Version zu alt ist, um mit dem Server zu sprechen (Synchronisierung,
/// Cloud-/KI-Funktionen). Hintergrund: Server-Schema und Edge-Function-Vertraege werden unabhaengig
/// vom Client weiterentwickelt, dieses Projekt hat keine formale API-Versionierung -- eine
/// Schema-Aenderung muss nicht rueckwaertskompatibel zu einer aelteren installierten Version sein.
/// `minSupportedBuildNumber` kommt von `app_config` (server-seitig von Hand gepflegt).
bool isAppUpdateRequired({required int currentBuildNumber, required int minSupportedBuildNumber}) =>
    currentBuildNumber < minSupportedBuildNumber;

/// Online-/Cloud-Funktionen sind gesperrt, weil die installierte Version zu alt fuer den aktuellen
/// Server-Stand ist. Nicht zu verwechseln mit `CloudUnavailable` (Netzfehler) oder `CloudNotAllowed`
/// (bewusste Nutzer-Einstellung) -- hier hilft nur ein Update, kein erneuter Versuch.
class AppUpdateRequiredException implements Exception {
  const AppUpdateRequiredException();
  @override
  String toString() => 'Ein Update ist erforderlich, bevor diese Funktion wieder verfügbar ist.';
}
