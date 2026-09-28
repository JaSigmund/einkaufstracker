insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.0', 'Grundpreis, Preisvergleich und Trends',
   '[
     "Jeder Bon-Artikel bekommt jetzt eine Produkt-Zuordnung und einen Grundpreis (€/kg, €/l, €/Stk)",
     "Duplikate zusammenfuehren: zwei versehentlich getrennte Produkte lassen sich unter \"Meine Produkte\" vereinen",
     "Neues Artikel-Detail: Preisverlauf und Haendlervergleich je Produkt (Tippen auf einen Artikel in der Auswertung)",
     "Neuer Trend-Tab in der Auswertung: Ausgaben der letzten 6 oder 12 Monate auf einen Blick",
     "Monatsbudget mit Fortschrittsbalken (Einstellungen → Monatsbudget)",
     "Bon-Daten lassen sich jetzt als CSV exportieren und teilen"
   ]'::jsonb,
   now());
