-- Standardkategorien (Vorlage, wird bei Registrierung in den Haushalt kopiert).
-- Als Migration, damit "supabase db push" sie mitliefert (handle_new_user liest default_categories).

insert into public.default_categories (name, icon, sort_order, is_storable) values
  ('Obst',                   'apple',      10, true),
  ('Gemüse',                 'carrot',     20, true),
  ('Fleisch & Wurst',        'meat',       30, true),
  ('Fisch',                  'fish',       40, true),
  ('Milch & Milchprodukte',  'milk',       50, true),
  ('Eier',                   'egg',        60, true),
  ('Brot & Backwaren',       'bread',      70, false),
  ('Käse',                   'cheese',     80, true),
  ('Getränke',               'drink',      90, true),
  ('Tiefkühl',               'snowflake', 100, true),
  ('Konserven & Trockenware','can',       110, true),
  ('Öle, Gewürze & Saucen',  'bottle',    120, true),
  ('Süßes & Snacks',         'candy',     130, true),
  ('Fertiggerichte',         'meal',      140, true),
  ('Haushalt & Drogerie',    'home',      150, false),
  ('Pfand',                  'recycle',   160, false),
  ('Sonstiges',              'other',     999, false)
on conflict (name) do nothing;
