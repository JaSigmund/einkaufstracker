insert into app_changelog (version, title, highlights, released_at) values
  ('1.3.0', 'Einkaufsliste, intuitivere Produktverwaltung, Haltbarkeits-Vorbelegung',
   '["Neuer Tab \"Liste\": offline nutzbar, nach Kategorie gruppiert, automatischer Vorschlag bei aufgebrauchten Nachkaufprodukten", "Produktname direkt auf der Inventar-Detailseite umbenennbar", "Bonzuordnung eines Inventar-Eintrags direkt loesbar oder aenderbar", "Neue Produkte bekommen Haltbarkeit-nach-Oeffnen, Lagerort und MHD/Verbrauchsdatum automatisch vorbelegt"]'::jsonb,
   now());
