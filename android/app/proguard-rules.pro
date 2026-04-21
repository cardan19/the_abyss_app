# ── Google Play Core (split-install / deferred components) ───────────────────
# Flutter's engine references Play Core classes even when you don't use them.
# Since we're distributing as a direct APK (not Play Store), these classes
# aren't present. Tell R8 to ignore the missing references instead of failing.
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ── Flutter engine ────────────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ── Flutter InAppWebView ──────────────────────────────────────────────────────
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-keep class androidx.webkit.** { *; }
-keep class android.webkit.** { *; }

# ── JavaScript bridge ─────────────────────────────────────────────────────────
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# ── Kotlin ────────────────────────────────────────────────────────────────────
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# ── Reflection & attributes ───────────────────────────────────────────────────
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable

# ── Networking ────────────────────────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**

# ── AndroidX ─────────────────────────────────────────────────────────────────
-keep class androidx.preference.** { *; }
-keep class androidx.lifecycle.** { *; }

# ── URL Launcher & Splash ─────────────────────────────────────────────────────
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class com.zeno.flutter_native_splash.** { *; }
