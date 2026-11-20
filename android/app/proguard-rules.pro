# ==============================================================================
# GitHub Nexus — R8 / ProGuard Release Optimization Rules
# ==============================================================================

# Preserve Flutter engine & generated plugin registrant
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Preserve GitHub Nexus native Activity, Foreground Service & Platform Channels
-keep class com.githubnexus.app.MainActivity { *; }
-keep class com.githubnexus.app.DeployForegroundService { *; }
-keep class com.githubnexus.app.DeployForegroundService$** { *; }

# Preserve flutter_secure_storage + AndroidX Security Crypto + Google Tink
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-keep class com.google.crypto.tink.shaded.protobuf.** { *; }
-dontwarn com.google.crypto.tink.**
-dontwarn javax.annotation.**

# Preserve file_picker native callbacks
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# Kotlin metadata & coroutines safety
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.coroutines.**

# Strip verbose debug logs in release builds
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
}
