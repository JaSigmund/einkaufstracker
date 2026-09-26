-- Rabatte, die sich auf den ganzen Bon beziehen (z.B. jö Rabattsammler 20 %), bekommen eine eigene Positionsart.
-- Bisher wurden sie als normaler Rabatt gespeichert und erbten im Nachtrag die Kategorie des Artikels darueber
-- (ein Getraenk war dadurch im Monat negativ). Als eigene Art stehen sie in der Auswertung getrennt.
--
-- Bestehende Zeilen korrigiert die App selbst beim naechsten Sync (ein neuer Enum-Wert darf in derselben
-- Transaktion noch nicht verwendet werden).
alter type public.item_kind add value if not exists 'bill_discount';
