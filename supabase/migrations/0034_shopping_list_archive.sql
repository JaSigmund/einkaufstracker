-- Einkaufsliste archivieren (ADR-043): "Einkauf abschliessen" nimmt die abgehakten Eintraege von der Liste, ohne sie zu loeschen.
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen (ADR).md
--
-- Eine Spalte statt eigener Tabelle: Eintraege desselben Abschlusses tragen denselben Zeitstempel, das ist die ganze Gruppierung. Aeltere
-- App-Versionen senden die Spalte nicht und lassen sie deshalb unveraendert; sie zeigen archivierte Eintraege weiter unter "Erledigt".

alter table public.shopping_list_items add column archived_at timestamptz;
