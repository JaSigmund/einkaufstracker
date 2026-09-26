-- Originalbelege zu Bons (Phase 2): Foto (ohne Zahlungsblock) oder PDF des digitalen Bons. Die Dateien liegen im
-- privaten Storage-Bucket "receipts" (Pfad {household_id}/{receipt_id}/{file_id}.{ext}, Zugriff per Haushalt, siehe
-- Policy receipts_storage_rw in 0001). Diese Tabelle verzeichnet sie, damit jedes Geraet sie beim Bon anzeigen kann.
-- Ein Bon kann mehrere Dateien haben (bis zu vier Fotoseiten).

create table public.receipt_files (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  receipt_id   uuid not null references public.receipts(id) on delete cascade,
  kind         text not null check (kind in ('pdf', 'image')),
  page_no      int  not null default 1,
  storage_path text not null,
  size_bytes   int,
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index on public.receipt_files (household_id);
create index on public.receipt_files (receipt_id);

alter table public.receipt_files enable row level security;
create policy receipt_files_all on public.receipt_files
  for all
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
create trigger trg_touch_receipt_files before update on public.receipt_files
  for each row execute function public.touch_updated_at();
