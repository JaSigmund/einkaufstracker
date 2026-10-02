-- Online-Preise: bessere Reihung der Suche (ADR-019, nach dem ersten echten Lauf am 2026-10-02).
-- 0018 ist auf Produktion eingespielt und bleibt unveraendert, die Funktion wird hier ersetzt.
--
-- Beobachtung an den echten Daten ("Vollmilch 1l"): ein Wortanfang-Treffer wie "BILLA Vollmilchglasur" stand vor "Schogetten
-- Vollmilch", und das Wort "1l" fand "Pasabahce Krug 1L". Neu:
--   * ganze Woerter zaehlen dreifach gegenueber Wortanfaengen (Vollmilch vor Vollmilchglasur),
--   * keine Laengennormalisierung mehr in ts_rank (sie bestrafte lange Namen so stark, dass ein Wortanfang-Treffer in
--     einem kurzen Namen einen ganzen Wort-Treffer in einem langen schlug), stattdessen entscheidet bei gleicher
--     Wertung der kuerzere Name,
--   * Suchwoerter mit Ziffern (Mengen wie 1l, 500g) werden ignoriert: sie unterscheiden Artikel kaum und treffen Fremdes.
create or replace function public.search_online_prices(
  q text,
  wanted_stores text[] default array['billa', 'spar'],
  per_store integer default 8
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
    select to_tsquery('simple', string_agg(t || ':*', ' | ')) as prefix_q,
           to_tsquery('simple', string_agg(t, ' | ')) as exact_q
    from tokens
  ),
  ranked as (
    select p.*,
           row_number() over (
             partition by p.store
             order by 3 * ts_rank(to_tsvector('simple', p.name), query.exact_q)
                        + ts_rank(to_tsvector('simple', p.name), query.prefix_q) desc,
                      length(p.name), p.name
           ) as rn
    from public.online_prices p, query
    where p.store = any(wanted_stores)
      and query.prefix_q is not null
      and to_tsvector('simple', p.name) @@ query.prefix_q
  )
  select r.store, r.external_id, r.name, r.price_cents, r.quantity, r.unit, r.base_unit, r.unit_price_norm_cents, r.seen_at
  from ranked r
  where r.rn <= least(greatest(per_store, 1), 20)
  order by r.store, r.rn;
$$;
