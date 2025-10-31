# proguard-rules.pro — ZenYourself (minimal + Play Core fix)

# --- Flutter/Embedding & Plugins (Einstiegs-APIs nicht aggressiv beschneiden)
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- Play Core / Deferred Components (behebt R8 "Missing class ... play.core.*")
# -> Voraussetzung: In build.gradle ist implementiert:
#    implementation "com.google.android.play:core:1.10.3"
-dontwarn com.google.android.play.**
-keep class com.google.android.play.** { *; }
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Flutter-spezifischer Deferred-Manager (wird von Embedding referenziert)
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-keep class io.flutter.embedding.android.FlutterPlayStoreSplitApplication { *; }

# --- (Optional) Logging-APIs harmlos stummschalten
-dontwarn org.slf4j.**
-dontwarn javax.annotation.**

# --- (Optional) Kotlin-Metadaten (hilft bei vereinzelter Reflektion)
-keepclassmembers class ** {
  @kotlin.Metadata *;
}

# --- (Optional) JSON-Reflektionsbibliotheken – nur auskommentiert, falls nötig
# Gson:
# -keep class com.google.gson.** { *; }
# -keep class * implements com.google.gson.TypeAdapterFactory
# -keepattributes Signature
# Moshi:
# -dontwarn com.squareup.moshi.**
# Jackson:
# -dontwarn com.fasterxml.jackson.**

# --- Empfohlene Attribute erhalten (meistens bereits im Default-ProGuard enthalten)
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
