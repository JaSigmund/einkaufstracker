-- Online-Preise: mehrere Online-Artikel je Produkt und Haendler (ADR-019, Wunsch von Jakob am 2026-10-02).
-- 0018 ist auf Produktion eingespielt und bleibt unveraendert, der Unique-Index wird hier ersetzt.
--
-- Beispiel: Es ist egal, ob Jakob Bio-Paprika oder normale Paprika kauft, beides ist sein Produkt "Paprika", bei Billa aber
-- sind es zwei Artikel. Bisher durfte ein Produkt je Haendler nur einen aktiven Online-Artikel haben. Neu: beliebig viele,
-- aber derselbe Artikel nur einmal je Produkt.
drop index if exists public.product_online_links_active;

create unique index product_online_links_active
  on public.product_online_links (household_id, product_id, store, external_id)
  where deleted_at is null;
