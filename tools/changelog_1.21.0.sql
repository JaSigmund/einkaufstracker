insert into app_changelog (version, title, highlights, released_at) values
  ('1.21.0', 'Trinkmenge mit Ziel, Alkohol und Koffein',
   '[
     "Schnell eintragen zeigt jetzt, wie viel du heute getrunken hast, im Vergleich zu deinem Ziel. Wasser und alle Getraenke zaehlen mit, auch das Wasser in Mischungen",
     "Ziel und Erinnerung stellst du dort oder bei den Richtwerten ein. Vorbelegt sind 1,5 Liter und eine Erinnerung um 16 Uhr, die fuer den Tag entfaellt, sobald du die Haelfte geschafft hast",
     "Tagebuch: Ab zwei Getraenken am Tag stehen sie in einer aufklappbaren Zeile, in den Tagessummen zaehlen sie weiter mit",
     "Alkohol und Koffein: Bei trinkbaren Produkten traegst du Vol.-% und mg je 100 ml ein, die Seite Naehrstoffe zeigt beides je Tag und Woche",
     "Mahlzeiten: Haushaltseinheiten bei Stueckware werden jetzt anteilig vom Bestand abgezogen"
   ]'::jsonb,
   now());
