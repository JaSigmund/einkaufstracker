# google_mlkit_text_recognition verweist auf optionale Schrifterkenner (Chinesisch, Japanisch, Koreanisch,
# Devanagari), die wir nicht einbinden (nur Latin). Ohne diese Regeln bricht R8 im Release-Build ab.
# Diese Regeln gehoeren auch in die produktive App (Phase 1).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit (Dokumentenscanner und Texterkennung) laedt Klassen und Optionen ueber Reflection/Parcelable und die
# Play-Dienste. Ohne diese Regeln benennt R8 sie um oder entfernt Felder: der Scanner startet im Release-Build
# mit einer NullPointerException, obwohl er im Debug-Build laeuft.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google.android.gms.mlkit.** { *; }
-keep class dev.flutter.** { *; }
-keep class com.google_mlkit_document_scanner.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }

# flutter_local_notifications (Fehlerbericht "Ablauf-Erinnerung kommt nicht an", 2026-10-02): das Plugin
# serialisiert geplante Erinnerungen intern mit Gson und ruft seinen BroadcastReceiver ueber den
# Klassennamen auf, um die Erinnerung beim Ausloesen des Alarms zu posten. Ohne diese Regeln benennt/
# entfernt R8 im Release-Build genau diese Klassen: die Planung (reiner Dart/Plugin-Methodenkanal-Aufruf)
# schlaegt dadurch NICHT fehl und wird korrekt geloggt, aber beim Ausloesen des Alarms findet Android die
# Receiver-Klasse nicht mehr -- die Benachrichtigung erscheint nie, ganz ohne sichtbaren Fehler.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
