-- Verbrauchsbilanz und Gegenbuchungen (Phase 7d, ADR-025, Doku 15 §4 und FR-12)
--
-- Seit Phase 7b nimmt die App eine geloeschte oder geaenderte Mahlzeit ueber eine positive `adjustment`-Buchung mit
-- `meal_id` zurueck (das Ledger bleibt append-only). Die View v_weekly_stock_flow (0003) kannte diese Buchungen nicht:
-- sie zaehlte sie als Inventur-Korrektur (`adjusted`), und `eaten` blieb nach dem Loeschen einer Mahlzeit zu hoch.
--
-- Jetzt gilt:
--   eaten    = -(Summe der Mahlzeit-Abzuege + Summe der Gegenbuchungen mit meal_id)  -> netto
--   adjusted = nur Korrekturen OHNE Mahlzeit-Bezug
-- Eine Gegenbuchung wird der Woche der ersten Abzugsbuchung ihrer Mahlzeit zugeordnet (nicht der Woche, in der man
-- loescht oder aendert), damit eine Woche nie negative Mengen zeigt. Dadurch ist `net_change` je Woche nicht mehr
-- strikt "Bestandsaenderung im Kalenderwochen-Sinn", sondern die in sich stimmige Summe der oben genannten Spalten;
-- die Summe ueber alle Wochen bleibt unveraendert die Gesamtbewegung des Ledgers.
--
-- Spalten und Reihenfolge bleiben identisch zu 0003 (CREATE OR REPLACE VIEW erlaubt keine Aenderung daran).
create or replace view public.v_weekly_stock_flow
with (security_invoker = true) as
with flow as (
  select
    m.*,
    case
      when m.type = 'adjustment' and m.meal_id is not null then coalesce(
        (select min(d.occurred_at)
           from public.inventory_movements d
          where d.meal_id = m.meal_id and d.type = 'meal' and d.deleted_at is null),
        m.occurred_at)
      else m.occurred_at
    end as flow_at
  from public.inventory_movements m
  where m.deleted_at is null
)
select
  f.household_id,
  date_trunc('week', f.flow_at at time zone 'Europe/Vienna')::date as week,
  f.product_id,
  f.unit,
  sum(f.quantity_delta) filter (where f.type = 'purchase')                                            as purchased,
  -sum(f.quantity_delta) filter (where f.type = 'meal' or (f.type = 'adjustment' and f.meal_id is not null)) as eaten,
  -sum(f.quantity_delta) filter (where f.type = 'consumed')                                           as consumed_manual,
  -sum(f.quantity_delta) filter (where f.type = 'discarded')                                          as discarded,
  sum(f.quantity_delta) filter (where f.type = 'adjustment' and f.meal_id is null)                    as adjusted,
  sum(f.quantity_delta)                                                                               as net_change
from flow f
group by 1, 2, 3, 4;
