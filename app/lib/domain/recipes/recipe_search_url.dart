/// Baut eine Such-URL fuer eine vorgeschlagene oder gespeicherte Rezeptidee (ADR-021). Die App
/// generiert selbst keine Kochanleitung und kopiert/speichert keine fremden Inhalte (Urheberrecht,
/// siehe Systemregeln) -- sie fuehrt stattdessen zur echten, oeffentlichen Rezeptseite.
///
/// **Bewusst keine direkte URL zur internen Suche von `gutekueche.at`:** deren `robots.txt`
/// (geprueft 2026-10-01) sperrt `/suche` und `/*suche` ausdruecklich fuer alle Crawler, und das
/// Suchformular selbst ist rein JavaScript-gesteuert (kein erkennbares URL-Schema zum Nachbauen).
/// Automatisiert genau diesen gesperrten Pfad anzusteuern waere derselbe Fehler, den Jakob bei
/// ADR-019/ADR-021 bereits explizit abgelehnt hat (kein automatisiertes Auslesen gegen den
/// erklaerten Willen des Seitenbetreibers, R-15).
///
/// Stattdessen eine **auf die Domain eingeschraenkte Google-Suche** (`site:`-Operator): landet
/// typischerweise auf der echten, oeffentlich indexierten Rezeptseite (die normalen Rezeptseiten
/// sind in der robots.txt NICHT gesperrt, nur die interne Suche), ohne die gesperrte Suchfunktion
/// selbst anzusteuern oder eine bestimmte URL-Struktur zu erraten.
///
/// **Oeffnen:** empfohlen ueber den externen Browser (`url_launcher`), nicht per eingebetteter
/// WebView -- `gutekueche.at` setzt `X-Frame-Options: SAMEORIGIN` (geprueft 2026-10-01), eine
/// Einbettung per `<iframe>` im Flutter-Web/PWA-Build waere dadurch blockiert. Natives Android/iOS
/// waere von `webview_flutter` aus technisch nicht betroffen (keine Browser-Iframe-Einbettung), aber
/// der externe Browser funktioniert plattformuebergreifend einheitlich und ist einfacher.
String buildRecipeSearchUrl(String recipeTitle, {String site = 'gutekueche.at'}) {
  final query = Uri.encodeQueryComponent('site:$site ${recipeTitle.trim()} rezept');
  return 'https://www.google.com/search?q=$query';
}
