# Flutter obfuscation rules
-keep class io.flutter.** { *; }
-keep class androidx.** { *; }
-dontwarn io.flutter.**

# Hide Flutter framework signatures
-repackageclasses 'com.native.core'
-allowaccessmodification
-mergeinterfacesaggressively

# Obfuscate class names
-keepclassmembers class * {
    native <methods>;
}

# Remove Flutter debugging information
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# Obfuscate Firebase and Google services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Hide application signatures
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Rename packages to look native
-repackageclasses 'com.transport.core'

# Remove source file names and line numbers
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable

# Advanced obfuscation
-overloadaggressively
-repackageclasses
-allowaccessmodification
-mergeinterfacesaggressively