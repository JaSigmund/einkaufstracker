/// "Nochmal essen": die am haeufigsten erfassten Mahlzeiten als Schnellauswahl (Doku 15 §3.3: "Snack/Getraenk in
/// zwei Taps aus Favoriten"). Es gibt keine eigene Favoritenliste zu pflegen, die Haeufigkeit im Tagebuch ersetzt sie.
/// Reine Funktion ohne Datenbankzugriff.
library;

/// Eine erfasste Mahlzeit fuer die Auswahl (unabhaengig von der Datenbank-Klasse).
typedef FrequentCandidate = ({String id, String title, DateTime eatenAtUtc});

/// Eine Gruppe gleich benannter Mahlzeiten: [latestId] ist die zuletzt erfasste, sie dient als Vorlage.
typedef FrequentMeal = ({String latestId, String title, int count});

/// Fasst gleich benannte Mahlzeiten zusammen (ohne Gross-/Kleinschreibung und Leerzeichen am Rand) und liefert die
/// [limit] haeufigsten, bei gleicher Anzahl die zuletzt gegessenen zuerst. Der Titel stammt von der juengsten
/// Mahlzeit der Gruppe. Mahlzeiten ohne Titel zaehlen nicht. Mit [since] zaehlen nur Mahlzeiten ab diesem Zeitpunkt, damit
/// ein Gericht von vor einem Jahr keinen Platz belegt.
List<FrequentMeal> frequentMeals(Iterable<FrequentCandidate> meals, {int limit = 6, DateTime? since}) {
  final groups = <String, ({FrequentCandidate latest, int count})>{};
  for (final m in meals) {
    final key = m.title.trim().toLowerCase();
    if (key.isEmpty) continue;
    if (since != null && m.eatenAtUtc.isBefore(since)) continue;
    final g = groups[key];
    if (g == null) {
      groups[key] = (latest: m, count: 1);
    } else {
      groups[key] = (latest: m.eatenAtUtc.isAfter(g.latest.eatenAtUtc) ? m : g.latest, count: g.count + 1);
    }
  }
  final sorted = groups.values.toList()
    ..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : b.latest.eatenAtUtc.compareTo(a.latest.eatenAtUtc);
    });
  return [for (final g in sorted.take(limit)) (latestId: g.latest.id, title: g.latest.title.trim(), count: g.count)];
}
