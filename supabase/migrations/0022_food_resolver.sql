-- Zuordnung von Zutaten zu Naehrwerten ("Food Resolver", Phase N1, ADR-031).
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/22 Konzept Naehrwert-Abdeckung.md §3
--
-- Ein Name wie ihn die Foto-KI oder der Nutzer liefert ("Paprika", "Hähnchenbrust", "Hüttenkäse") wird einem Eintrag der
-- Lebensmitteldatenbank (bls_foods) zugeordnet. Schichten, von oben nach unten (die erste sichere gewinnt):
--   1. Gedaechtnis des Haushalts (household_food_links): was der Nutzer schon bestaetigt oder geaendert hat
--   2. Synonyme (food_synonyms, global): Alltagsbegriffe, die in der BLS anders heissen (Brokkoli = Broccoli)
--   3. Suche ueber die Namen der BLS mit Wertung (ganzes Wort, Wortanfang, Teil eines zusammengesetzten Worts, "roh" bevorzugt,
--      Gerichte der Gruppen X und Y abgewertet)
-- Alles in SQL, damit App, Edge Function und Test dieselbe Implementierung nutzen; der Golden-Test (run_schema_tests.py) laeuft
-- mit der echten BLS gegen genau diese Funktionen.

-- ---------------------------------------------------------------------------------------------------------------
-- Normalisierung
-- ---------------------------------------------------------------------------------------------------------------

-- Kernwoerter eines Namens: klein, nur Buchstaben, ohne Fuell- und Zustandswoerter, grob in den Singular gesetzt
-- ("200 g frische Tomaten" -> "tomate"). Reihenfolge bleibt erhalten. Der Zustand ("gekocht") steht in food_state.
create or replace function public.food_core(txt text)
returns text
language sql immutable
as $$
  select coalesce(string_agg(
           case when c ~ 'en$' and c !~ 'chen$' and length(c) >= 5 then left(c, length(c) - 1)
                when c ~ '(ln|rn)$' and length(c) >= 6 then left(c, length(c) - 1)
                when c ~ '(is|os|as)$' and length(c) >= 5 and c not in ('ananas', 'kokos', 'kürbis', 'reis') then left(c, length(c) - 1)
                else c end,
           ' ' order by ord), '')
  from unnest(regexp_split_to_array(
         regexp_replace(translate(lower(coalesce(txt, '')), 'éèêàâîïôûç', 'eeeaaiiouc'), '(^|[^0-9])1[,.]5 ?%?', '\1 fettarm ', 'g'),
         '[^a-zäöüß]+')) with ordinality as x(t, ord),
       lateral (select regexp_replace(t, '^(rot|gelb|grün|weiß|weiss|schwarz|braun|fettarm)(e[rsnm]?)$', '\1') as c) as y
  where length(t) >= 2
    and t not in ('und', 'mit', 'ohne', 'in', 'im', 'vom', 'von', 'aus', 'der', 'die', 'das', 'ein', 'eine', 'einer', 'einem',
                  'etwas', 'ca', 'circa', 'frisch', 'frische', 'frischer', 'frisches', 'frischen', 'ganze', 'ganzer', 'ganzes',
                  'kleine', 'kleiner', 'kleines', 'grosse', 'große', 'großer', 'großes', 'stueck', 'stück', 'stücke',
                  'scheibe', 'scheiben', 'portion', 'portionen', 'gramm', 'kg', 'ml', 'el', 'tl', 'bio', 'natur', 'fett')
    and t !~ '^(roh(e[rsnm]?)?|gerieben.*|geschnitten.*|gewürfelt.*|gehackt.*|(hart|weich)?gekocht.*|gebraten.*|frittiert.*|gebacken.*|ueberbacken.*|überbacken.*|geschmort.*|gedünstet.*|gedämpft.*|getrocknet.*|gegrillt.*|geräuchert.*|tiefgefroren.*|gefroren.*)$'
$$;

-- Schluessel fuer Synonyme und Gedaechtnis: die Kernwoerter alphabetisch sortiert ("rote Paprika" = "Paprika rot").
create or replace function public.food_key(txt text)
returns text
language sql immutable
as $$
  select coalesce(string_agg(t, ' ' order by t), '')
  from unnest(string_to_array(public.food_core(txt), ' ')) as t
  where t <> ''
$$;

-- Zustandswunsch im Namen: roh, gekocht, gebraten, frittiert, gebacken, geschmort, gedünstet, getrocknet, gegrillt. Sonst null.
create or replace function public.food_state(txt text)
returns text
language sql immutable
as $$
  select case
    when lower(coalesce(txt, '')) ~ '(^|[^a-zäöüß])roh(e[rsnm]?)?([^a-zäöüß]|$)' then 'roh'
    when lower(coalesce(txt, '')) ~ 'gekocht' then 'gekocht'
    when lower(coalesce(txt, '')) ~ 'gebraten' then 'gebraten'
    when lower(coalesce(txt, '')) ~ 'frittiert' then 'frittiert'
    when lower(coalesce(txt, '')) ~ '(gebacken|überbacken|ueberbacken)' then 'gebacken'
    when lower(coalesce(txt, '')) ~ 'geschmort' then 'geschmort'
    when lower(coalesce(txt, '')) ~ '(gedünstet|gedämpft)' then 'gedünstet'
    when lower(coalesce(txt, '')) ~ 'getrocknet' then 'getrocknet'
    when lower(coalesce(txt, '')) ~ 'gegrillt' then 'gegrillt'
    else null end
$$;

-- Die BLS-Codes haben 7 Zeichen. Die letzten zwei sind die Zubereitung: 00 roh, 32 gekocht, 42 geschmort, 52 gedünstet,
-- 62 gebacken (Ofen), 72 gegrillt, 82 gebraten (Pfanne). Zu "Karotte/Möhre, roh" (G620100) gehoert "..., gekocht" (G620132).
-- Wer "gekochter Reis" sagt, bekommt so den gekochten Eintrag, auch wenn der Treffer ueber ein Synonym kam, das auf den
-- rohen Eintrag zeigt.
create or replace function public.food_state_suffix(want text)
returns text
language sql immutable
as $$
  select case want when 'gekocht' then '32' when 'geschmort' then '42' when 'gedünstet' then '52' when 'gebacken' then '62'
                   when 'gegrillt' then '72' when 'gebraten' then '82' else null end
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Synonyme (global, schreibgeschuetzt wie bls_foods) und Gedaechtnis des Haushalts (synchronisiert)
-- ---------------------------------------------------------------------------------------------------------------
create table public.food_synonyms (
  term_norm text primary key,                                   -- food_key des Alltagsbegriffs
  bls_code  text not null references public.bls_foods(bls_code) on delete cascade,
  note      text
);
alter table public.food_synonyms enable row level security;
create policy food_synonyms_read on public.food_synonyms for select using (auth.role() = 'authenticated');

create table public.household_food_links (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name_norm    text not null,                                   -- food_key des Namens, wie der Nutzer ihn zuordnete
  bls_code     text not null references public.bls_foods(bls_code) on delete cascade,
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create unique index household_food_links_active on public.household_food_links (household_id, name_norm) where deleted_at is null;

alter table public.household_food_links enable row level security;
create policy household_food_links_all on public.household_food_links for all
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
create trigger trg_touch_household_food_links before update on public.household_food_links
  for each row execute function public.touch_updated_at();

-- Die App schickt den Namen, wie der Nutzer ihn sah ("Frische Paprika"), der Server macht daraus den Schluessel ("paprika"):
-- so gibt es die Normalisierung nur einmal (in food_key) und keine zweite Fassung in der App, die auseinanderlaufen koennte.
create function public.normalize_food_link()
returns trigger
language plpgsql
as $$
begin
  new.name_norm := public.food_key(new.name_norm);
  if new.name_norm = '' then
    raise exception 'Name ergibt nach der Normalisierung nichts' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger trg_normalize_food_links before insert or update of name_norm on public.household_food_links
  for each row execute function public.normalize_food_link();

-- ---------------------------------------------------------------------------------------------------------------
-- Suche
-- ---------------------------------------------------------------------------------------------------------------
-- Liefert die [n] besten Treffer zu [q]. method: memory | synonym | search. confidence (nur fuer Rang 1):
--   sure   = Gedaechtnis oder Synonym
--   auto   = Suche, alle Suchwoerter als ganzes Wort, der Eintrag beginnt mit einem Suchwort ("Apfel roh"), und entweder heisst
--            er genau so oder der Abstand zum zweiten Treffer ist klar und er ist kein Gericht/Gebaeck (Gruppen X, Y, D)
--   unsure = alles andere (die App fragt nach oder zeigt "unbekannt")
-- [p_household] waehlt das Gedaechtnis eines Haushalts (Aufruf mit Service-Schluessel); ohne Angabe gilt, was die Row Level
-- Security dem Aufrufer zeigt. [p_loose] haengt Treffer an, die nur einen Teil der Suchwoerter enthalten (fuer die Handsuche).
create or replace function public.search_bls_foods(
  q text,
  n integer default 8,
  p_household uuid default null,
  p_loose boolean default false
)
returns table (
  bls_code text, name_de text, score numeric, method text, rank integer, confidence text, coverage numeric,
  kcal numeric, protein_g numeric, fat_g numeric, sat_fat_g numeric, carbs_g numeric, sugar_g numeric, fiber_g numeric, salt_g numeric
)
language sql stable security invoker
set search_path = public
as $$
  with params as (
    select public.food_core(q) as core, public.food_key(q) as key, public.food_state(q) as want, least(greatest(n, 1), 25) as lim
  ),
  qt as (
    select t, ord from params, unnest(string_to_array(params.core, ' ')) with ordinality as x(t, ord) where t <> ''
  ),
  ntok as (select greatest(count(*), 1) as k from qt),
  -- Schicht 1: Gedaechtnis
  mem as (
    select b.bls_code, 1000::numeric as score, 'memory'::text as method, 1.0::numeric as coverage, false as exact_name
    from public.household_food_links l
    join public.bls_foods b on b.bls_code = l.bls_code
    cross join params
    where l.deleted_at is null and params.key <> '' and l.name_norm = params.key
      and (p_household is null or l.household_id = p_household)
  ),
  -- Schicht 2: Synonyme
  syn as (
    select b.bls_code, 900::numeric as score, 'synonym'::text as method, 1.0::numeric as coverage, false as exact_name
    from public.food_synonyms s
    join public.bls_foods b on b.bls_code = s.bls_code
    cross join params
    where params.key <> '' and s.term_norm = params.key
  ),
  -- Schicht 2b: genau eines der Suchwoerter ist ein Synonym, die uebrigen sind Beiwerk ("Mozzarella Kugeln"). Nur wenn der ganze
  -- Name weder im Gedaechtnis noch als Synonym steht.
  synpart as (
    select b.bls_code, -500::numeric as score, 'synonym'::text as method, 0.99::numeric as coverage, false as exact_name
    from (select qt.t from qt) q1
    join public.food_synonyms s on s.term_norm = q1.t
    join public.bls_foods b on b.bls_code = s.bls_code
    where (select count(*) from qt) > 1
      and not exists (select 1 from mem) and not exists (select 1 from syn)
      and (select count(*) from qt q2 join public.food_synonyms s2 on s2.term_norm = q2.t) = 1
  ),
  -- Schicht 3: Suche ueber die Namen
  words as (
    select b.bls_code, b.name_de, lower(b.name_de) as lname,
           array(select w from unnest(regexp_split_to_array(lower(b.name_de), '[^a-zäöüß]+')) as w where length(w) >= 2) as w,
           array(select w from unnest(regexp_split_to_array(split_part(lower(b.name_de), ' ', 1), '[^a-zäöüß]+')) as w where length(w) >= 2) as head
    from public.bls_foods b
    where exists (select 1 from qt)
  ),
  tok as (
    select r.bls_code, qt.t,
           case
             when qt.t = any(r.w) then 2.0
             when length(qt.t) >= 3 and exists (select 1 from unnest(r.w) x where x like qt.t || '%') then 1.0
             when length(qt.t) >= 6 and exists (select 1 from unnest(r.w) x where length(x) >= 6 and (x like '%' || qt.t or qt.t like x || '%')) then 0.75
             when length(qt.t) >= 8 and exists (select 1 from unnest(r.w) x where length(x) >= 4 and (qt.t like x || '%' or qt.t like '%' || x)) then 0.75
             else 0 end as s
    from words r cross join qt
  ),
  agg as (
    select bls_code, sum(s) as total, count(*) filter (where s > 0) as hit
    from tok group by bls_code
  ),
  srch as (
    select w.bls_code,
           (10 * a.total
            + case when w.head && array(select t from qt) then 6 else 0 end
            + case
                when params.want is null then
                  (case when 'roh' = any(w.w) then 5 else 0 end)
                  - (case when w.w && array['gekocht','gebraten','frittiert','gebacken','geschmort','gedünstet','getrocknet','konserve','pulver','paniert','mariniert','fertigprodukt','überbacken','gegrillt','tiefgefroren','gesüßt','gezuckert','geräuchert','eingelegt']
                          or (left(w.bls_code, 1) not in ('X', 'Y') and (w.lname like '% mit %' or w.lname like '% und %')) then 6 else 0 end)
                when params.want = 'roh' then (case when 'roh' = any(w.w) then 8 else 0 end)
                else (case when exists (select 1 from unnest(w.w) x where x like params.want || '%') then 8 else 0 end)
              end
            - case when left(w.bls_code, 1) in ('X', 'Y') then (case when a.total >= 2.0 * (select k from ntok) then 6 else 12 end) else 0 end
            - case when w.w && array['glutenfrei','laktosefrei','vegan','vegetarisch','zuckerfrei','energiereduziert','fettreduziert','kohlenhydratreduziert','alkoholfrei','entkoffeiniert','koffeinreduziert']
                    and not exists (select 1 from qt where qt.t = any(array['glutenfrei','laktosefrei','vegan','vegetarisch','zuckerfrei','energiereduziert','fettreduziert','alkoholfrei','entkoffeiniert'])) then 8 else 0 end
            - 0.15 * length(w.name_de))::numeric as score,
           (a.total / (2.0 * (select k from ntok)))::numeric as coverage,
           (a.hit = (select k from ntok)) as strict,
           (public.food_core(w.name_de) = params.core) as exact_name,
           (w.head && array(select t from qt)) as head_first
    from words w join agg a on a.bls_code = w.bls_code cross join params
    where a.hit > 0 and (a.hit = (select k from ntok) or p_loose)
  ),
  merged as (
    select bls_code, score, method, coverage, exact_name, true as head_first from mem
    union all select bls_code, score, method, coverage, exact_name, true from syn
    union all select bls_code, score, method, coverage, exact_name, true from synpart
    union all select bls_code, score - case when strict then 0 else 40 end, 'search', coverage, exact_name, head_first from srch
  ),
  best as (
    select distinct on (m.bls_code) m.bls_code, m.score, m.method, m.coverage, m.exact_name, m.head_first
    from merged m order by m.bls_code, m.score desc
  ),
  ranked as (
    select b.*, row_number() over (order by b.score desc, length(f.name_de), f.name_de) as rank,
           b.score - lead(b.score) over (order by b.score desc, length(f.name_de), f.name_de) as gap
    from best b join public.bls_foods f on f.bls_code = b.bls_code
  ),
  -- gewuenschter Zustand: statt des rohen Eintrags das Geschwister mit der passenden Zubereitung, falls es eines gibt
  final as (
    select r.*,
           coalesce(
             (select s.bls_code from public.bls_foods s, params
              where params.want is not null and public.food_state_suffix(params.want) is not null
                and right(r.bls_code, 2) = '00'
                and s.bls_code = left(r.bls_code, 5) || public.food_state_suffix(params.want)),
             r.bls_code) as target_code
    from ranked r
  )
  select r.target_code, f.name_de, round(r.score, 2), r.method, r.rank::integer,
         case
           when r.rank = 1 and r.method in ('memory', 'synonym') and r.coverage >= 1.0 then 'sure'
           when r.rank = 1 and r.method = 'synonym' then 'auto'
           when r.rank = 1 and r.method = 'search' and r.coverage >= 1.0 and r.head_first
                and (r.exact_name or ((r.gap is null or r.gap >= 6) and left(r.bls_code, 1) not in ('X', 'Y', 'D'))) then 'auto'
           else 'unsure' end,
         round(r.coverage, 2),
         f.kcal, f.protein_g, f.fat_g, f.sat_fat_g, f.carbs_g, f.sugar_g, f.fiber_g, f.salt_g
  from final r
  join public.bls_foods f on f.bls_code = r.target_code
  cross join params
  where r.rank <= params.lim
  order by r.rank;
$$;
