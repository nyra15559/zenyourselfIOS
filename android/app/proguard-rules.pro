# proguard-rules.pro — ZenYourself (minimal, sicher)

# --- Flutter/Embedding: Einstiegs-APIs nicht aggressiv beschneiden -----------
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }

# --- (Optional) Logging-API-Signaturen (harmlos, falls nicht genutzt) --------
-dontwarn org.slf4j.**
-dontwarn javax.annotation.**

# --- (Optional) Kotlin-Reflektion (nur wenn tatsächlich genutzt) -------------
# -keep class kotlin.reflect.** { *; }
# -keepclassmembers class ** {
#   @kotlin.Metadata *;
# }

# --- (Optional) Gson/Moshi/Jackson Modelle via Reflektion (falls vorhanden) --
# Gson:
# -keep class com.google.gson.** { *; }
# -keep class * implements com.google.gson.TypeAdapterFactory
# -keepattributes Signature
# Moshi:
# -dontwarn com.squareup.moshi.**
# Jackson:
# -dontwarn com.fasterxml.jackson.**

# Hinweis:
# Viele Flutter-Apps brauchen hier GAR NICHTS. Dieser Stub ist konservativ.
# Wenn ein Plugin zur Laufzeit reflektiert und etwas fehlt, melden — wir ergänzen gezielt.
