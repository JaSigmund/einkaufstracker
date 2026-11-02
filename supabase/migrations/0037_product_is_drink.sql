-- Trinkbare Produkte (ADR-048, Doku 26): die Entscheidung des Nutzers, ob ein Produkt trinkbar ist.
--
-- null heisst "die Regel entscheidet" (app/lib/domain/products/drinkable.dart). Die Regel laeuft in der App beim Lesen statt einmalig hier, damit sie
-- auch fuer Produkte gilt, die spaeter vom Bon kommen oder erst dann eine Kategorie bekommen.

alter table public.products add column is_drink boolean;
