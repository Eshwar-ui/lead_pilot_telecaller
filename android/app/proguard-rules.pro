# R8 keep rules for release builds.
#
# Only rules this app actually needs are here. Most plugins ship their own
# consumer rules inside their AAR (Firebase, media3/ExoPlayer behind just_audio,
# file_picker), and the Android Gradle Plugin generates keeps for every class
# named in the merged manifest — so MainActivity, CallNotesOverlayService and
# CallDetectionService are covered without being listed.
#
# Verify after adding a plugin or bumping one:
#   flutter build apk --release
#   then exercise a scheduled follow-up reminder and a call capture on a device.

# ── flutter_local_notifications ───────────────────────────────────────────
# The one plugin here that genuinely breaks under R8. It persists each
# scheduled notification as Gson JSON and deserialises it later — from
# ScheduledNotificationReceiver on the alarm, and again after a reboot — using
# RuntimeTypeAdapterFactory, which resolves types by their CLASS NAME at
# runtime. Obfuscate those names and every reschedule silently fails: no error,
# no crash, the reminder simply never fires. That is the whole 1-hour /
# 5-minute / on-time follow-up reminder chain, so it must not be shrunk.
# The plugin ships no consumer rules of its own (checked in 18.0.1).
-keep class com.dexterous.** { *; }

# Gson's own reflection requirements. Generic signatures must survive or
# TypeToken cannot reconstruct the parameterised types the plugin stores.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod
-dontwarn sun.misc.**
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type

# ── Core library desugaring ───────────────────────────────────────────────
# isCoreLibraryDesugaringEnabled is on (flutter_local_notifications requires
# it for java.time on older Android). R8 warns about the desugared stubs it
# rewrites away.
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
