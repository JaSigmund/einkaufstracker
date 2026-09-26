-- Vorbereitung fuer den Bon-Import (Phase 2):
-- 1. receipts.external_id: eindeutige Kennung des Kaufs, bei Billa die "Re-Nr" (Filiale-Datum-Kassa-Bonnummer).
--    Sie steht auf Papier und digital gleich, damit laesst sich derselbe Einkauf nicht doppelt importieren,
--    auch nicht einmal als Foto und einmal als PDF.
-- 2. receipt_items.tax_code: Steuerbuchstabe des Bons (B, C, D, H ...), Grundlage der Steuerblock-Pruefung.
-- 3. Quelle 'pdf_text': Bon aus der Textebene eines digitalen Bons, ohne OCR und ohne Cloud.

alter table public.receipts add column external_id text;

create unique index receipts_external_id_uniq
  on public.receipts (household_id, external_id)
  where external_id is not null and deleted_at is null;

alter table public.receipt_items add column tax_code text;

alter type public.ocr_source add value if not exists 'pdf_text';
