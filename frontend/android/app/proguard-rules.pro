# App R8 rules, added to release builds by the Flutter Gradle plugin after
# its own (flutter_proguard_rules.pro) and each plugin's consumer rules.
# Check every rule with an obfuscated release on a device
# (tool/build_android_release.sh, docs/deployment.md).

# shared_preferences_android 2.5.x calls these classes from Dart through JNI
# (jnigen bindings in lib/src/messages.g.jni.dart) and ships no consumer
# rules. R8 cannot see calls made from Dart, so without this it strips them and
# release builds hang on the splash screen with
#   NoSuchMethodError: SharedPreferencesApiRegistrar.getAll(...)
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Kotlin runtime classes that Dart reaches through JNI by name: package:jni
# (suspend calls: Continuation, Result, COROUTINE_SUSPENDED) and the JNI method
# signatures of the plugins above (Unit, DefaultConstructorMarker,
# EnumEntries). R8 would rename them, so the lookups fail at runtime with
# NoSuchMethodError or ClassNotFoundException.
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep interface kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt** { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
-keep interface kotlin.enums.EnumEntries { *; }
