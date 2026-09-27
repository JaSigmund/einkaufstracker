-- Behebt einen Sync-Fehler (Fehlerbericht "Synchronisierung", 2026-09-27): der Client sendet seit der
-- lernenden Produktzuordnung (ADR-010, product_aliases) immer ein deleted_at-Feld mit, das es hier bisher
-- nicht gab ("PGRST204: Could not find the 'deleted_at' column of 'product_aliases'"). Dadurch blieben
-- gelernte Zuordnungen dauerhaft in der Outbox haengen. category_aliases hat dieselbe Spalte bereits.

alter table public.product_aliases add column deleted_at timestamptz;
