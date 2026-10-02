/// Takt der automatischen Synchronisierung (ADR-018, Phase 6). Reine Funktionen ohne Zeit- oder Netzzugriff.
///
/// Allein im Haushalt reicht alle 2 Minuten (zusaetzlich zum Sync nach jeder Aenderung, beim Zurueckkehren in die App
/// und wenn das Netz zurueckkommt). Sobald mehrere Personen im Haushalt sind, soll eine Aenderung der anderen
/// schneller ankommen, sonst arbeitet man laenger auf einem veralteten Stand (gemeinsame Einkaufsliste): dann alle
/// 30 Sekunden. Kein Realtime, siehe ADR-018.
library;

/// Grundtakt des Timers in der App. Der eigentliche Sync-Abstand ist ein Vielfaches davon.
const syncTickPeriod = Duration(seconds: 30);

const soloSyncInterval = Duration(minutes: 2);
const sharedSyncInterval = Duration(seconds: 30);

/// Wie oft synchronisiert wird, abhaengig von der Zahl der Haushaltsmitglieder (unter 1 zaehlt wie 1).
Duration syncIntervalFor(int members) => members > 1 ? sharedSyncInterval : soloSyncInterval;

/// Ist beim naechsten Timer-Tick eine Synchronisierung faellig? [sinceLastSync] ist die Zeit seit dem letzten
/// erfolgreichen Sync, `null` wenn es noch keinen gab. Eine Sekunde Toleranz, damit ein Tick, der knapp vor dem Ablauf
/// des Abstands kommt, nicht einen ganzen weiteren Takt verschenkt.
bool isSyncDue({required int members, required Duration? sinceLastSync}) {
  if (sinceLastSync == null) return true;
  return sinceLastSync >= syncIntervalFor(members) - const Duration(seconds: 1);
}

/// Wie lange die Mitgliederzahl im Speicher gilt, bevor sie wieder beim Server erfragt wird. Aendert sich selten,
/// deshalb nicht bei jedem Sync.
const householdSizeMaxAge = Duration(minutes: 10);

bool isHouseholdSizeStale({required DateTime? fetchedAt, required DateTime now}) =>
    fetchedAt == null || now.difference(fetchedAt) >= householdSizeMaxAge;
