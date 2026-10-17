-- Tageslimit der KI-Functions atomar pruefen (Codereview 2026-10-16, Fund S9)
--
-- Bisher zaehlten die Functions die Aufrufe der letzten 24 Stunden in llm_usage und riefen danach das Modell auf; die Zeile
-- kam erst nach der Antwort dazu. Parallele Anfragen sahen dieselbe Zahl und konnten das Limit so um die Zahl der
-- gleichzeitigen Aufrufe ueberschreiten. reserve_llm_call zaehlt und legt die Zeile in EINER Transaktion an, serialisiert je
-- Haushalt ueber eine Advisory-Sperre. Die Function traegt Tokens und Kosten danach in genau diese Zeile ein
-- (_shared/llm_usage.ts) oder loescht sie wieder, wenn der Modellaufruf scheitert (ein Fehlschlag zaehlt wie bisher nicht).
--
-- Nur die service_role (Edge Functions) darf reservieren; Clients lesen llm_usage weiterhin nur (Policy aus 0001).

create or replace function public.reserve_llm_call(p_household uuid, p_model text, p_limit integer)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  reserved uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('llm_usage:' || p_household::text, 0));
  if (select count(*) from public.llm_usage u
      where u.household_id = p_household and u.created_at >= now() - interval '24 hours') >= p_limit then
    return null;
  end if;
  insert into public.llm_usage (household_id, model, input_tokens, output_tokens, cost_micro_usd)
  values (p_household, p_model, 0, 0, 0)
  returning id into reserved;
  return reserved;
end;
$$;

revoke all on function public.reserve_llm_call(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.reserve_llm_call(uuid, text, integer) to service_role;
