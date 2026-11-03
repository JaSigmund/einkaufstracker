-- Barcodes loesen (Doku 27 Etappe E3, ADR-052): bisher liess sich ein Barcode nur umhaengen, indem man ihn erneut scannte.
-- Ein Soft-Delete wie bei den uebrigen synchronisierten Tabellen, damit das Loesen auch auf die anderen Geraete kommt. Wird derselbe
-- Barcode spaeter wieder zugeordnet, setzt die App deleted_at zurueck (Upsert auf household_id, ean).

alter table public.product_barcodes add column deleted_at timestamptz;
