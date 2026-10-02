import 'package:flutter/material.dart';

/// Anzeigenamen der Mahlzeitentypen (`meal_type`-Enum) in der Reihenfolge, in der sie zur Auswahl stehen.
const mealTypeLabels = <String, String>{
  'breakfast': 'Frühstück',
  'lunch': 'Mittagessen',
  'dinner': 'Abendessen',
  'snack': 'Snack',
  'drink': 'Getränk',
};

String mealTypeLabel(String type) => mealTypeLabels[type] ?? 'Mahlzeit';

IconData mealTypeIcon(String type) => switch (type) {
      'breakfast' => Icons.free_breakfast_outlined,
      'lunch' => Icons.lunch_dining_outlined,
      'dinner' => Icons.dinner_dining_outlined,
      'snack' => Icons.cookie_outlined,
      'drink' => Icons.local_drink_outlined,
      _ => Icons.restaurant_outlined,
    };

/// Vorschlag fuer den Mahlzeitentyp nach der Uhrzeit (Wiener Ortszeit, Doku 15 §3.1: "Mahlzeitentyp geraten").
String guessMealType(int hour) {
  if (hour < 4) return 'snack';
  if (hour < 10) return 'breakfast';
  if (hour < 15) return 'lunch';
  if (hour < 17) return 'snack';
  if (hour < 22) return 'dinner';
  return 'snack';
}
