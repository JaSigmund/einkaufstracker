# google_mlkit_text_recognition verweist auf optionale Schrifterkenner (Chinesisch, Japanisch, Koreanisch,
# Devanagari), die wir nicht einbinden (nur Latin). Ohne diese Regeln bricht R8 im Release-Build ab.
# Diese Regeln gehoeren auch in die produktive App (Phase 1).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
