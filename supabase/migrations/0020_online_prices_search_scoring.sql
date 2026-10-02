-- Online-Preise: Suche mit eigener Wertung statt ts_rank (ADR-019, nach dem ersten echten Lauf am 2026-10-02).
-- 0018 und 0019 sind auf Produktion eingespielt und bleiben unveraendert, die Funktion wird hier ersetzt.
--
-- Beobachtung an den echten Daten: ts_rank belohnt, wie oft ein Wort vorkommt. "Schogetten Vollmilch-Haselnuss" (das Wort
-- steckt zweimal darin, im Bindestrich-Wort und als Teil) stand deshalb vor einer echten "Clever Vollmilch". Und die Suche
-- nach "Vollmilch" lieferte Schokolade neben Milch.
-- Neu:
--   * Wertung je Suchwort: ganzes Wort = 2 Punkte, nur Wortanfang = 1 Punkt, die Summe zaehlt (alle Woerter einer
--     Anfrage zu treffen schlaegt eines zu treffen),
--   * optional [prefer_base] ('kg', 'l', 'stk'): Artikel mit derselben Basiseinheit wie das eigene Produkt stehen bei
--     gleicher Wertung vorn (Milch kommt in Litern, Schokolade in Kilogramm),
--   * danach der kuerzere Name.
drop function if exists public.search_online_prices(text, text[], integer);

create function public.search_online_prices(
  q text,
  wanted_stores text[] default array['billa', 'spar'],
  per_store integer default 8,
  prefer_base text default null
)
returns table (
  store text, external_id text, name text, price_cents integer, quantity numeric, unit text,
  base_unit text, unit_price_norm_cents integer, seen_at timestamptz
)
language sql stable security invoker
set search_path = public
as $$
  with tokens as (
    select distinct t from unnest(regexp_split_to_array(lower(coalesce(q, '')), '[^a-zäöüß]+')) as t where length(t) >= 2
  ),
  query as (
    select to_tsquery('simple', string_agg(t || ':*', ' | ')) as prefix_q from tokens
  ),
  candidates as (
    select p.*, to_tsvector('simple', p.name) as vec
    from public.online_prices p, query
    where p.store = any(wanted_stores)
      and query.prefix_q is not null
      and to_tsvector('simple', p.name) @@ query.prefix_q
  ),
  scored as (
    select c.store, c.external_id, c.name, c.price_cents, c.quantity, c.unit, c.base_unit, c.unit_price_norm_cents, c.seen_at,
           sum(case when c.vec @@ to_tsquery('simple', t.t) then 2
                    when c.vec @@ to_tsquery('simple', t.t || ':*') then 1
                    else 0 end) as score
    from candidates c cross join tokens t
    group by c.store, c.external_id, c.name, c.price_cents, c.quantity, c.unit, c.base_unit, c.unit_price_norm_cents, c.seen_at
  ),
  ranked as (
    select s.*,
           row_number() over (
             partition by s.store
             order by s.score desc,
                      case when prefer_base is not null and s.base_unit = prefer_base then 0 else 1 end,
                      length(s.name), s.name
           ) as rn
    from scored s
  )
  select r.store, r.external_id, r.name, r.price_cents, r.quantity, r.unit, r.base_unit, r.unit_price_norm_cents, r.seen_at
  from ranked r
  where r.rn <= least(greatest(per_store, 1), 20)
  order by r.store, r.rn;
$$;
