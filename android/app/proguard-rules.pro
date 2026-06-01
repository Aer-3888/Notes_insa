## Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

## Keep FlutterSecureStorage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

## WorkManager (background tasks)
-keep class androidx.work.** { *; }
## Native grades background worker — WorkManager instantiates it by class name
-keep class com.aer.notes_insa.GradesBackgroundWorker { *; }

## CameraX / ML Kit (mobile_scanner)
-keep class androidx.camera.** { *; }
-keep class com.google.mlkit.** { *; }

## Flutter engine references Play Core split-install classes for deferred components.
## This app doesn't use Play Store dynamic delivery, so suppress the missing-class warnings.
-dontwarn com.google.android.play.core.**
