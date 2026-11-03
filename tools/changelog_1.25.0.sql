insert into app_changelog (version, title, highlights, released_at) values
  ('1.25.0', 'Zuordnen, wo es auffaellt',
   '[
     "Neu: Ein Tipp auf eine Bon-Position zeigt Produkt, Kategorie und Von jemand anderem bezahlt; das Produkt laesst sich dort aendern",
     "Neu: Auf der Produktseite Barcodes scannen, umhaengen und loesen sowie Bon-Positionen zuordnen",
     "Haengst du einen Barcode an ein Produkt, bietet die App die Naehrwerte von Open Food Facts an",
     "Neu: Gelernte Begriffe zeigt, welche Zutaten und Bon-Texte sich die App gemerkt hat, zum Aendern und Vergessen",
     "Die Kategorie des Produkts gilt jetzt auch fuer seine Bon-Positionen, nach dem Bon-Import siehst du neue Produkte"
   ]'::jsonb,
   now());
