# Tasu — R8/ProGuard release ережелері.
#
# Flutter, Firebase Messaging, geolocator, image_picker, url_launcher,
# shared_preferences, package_info_plus плагиндері өз consumer-rules
# файлдарын әкеледі — сол себепті олар үшін қосымша ереже қажет емес.
# Төмендегілер — рефлексия/GSON қолданатын кітапханаларды сақтауға арналған
# қорғаныс ережелері (release-те кенеттен NoSuchMethod болмауы үшін).

# --- Flutter engine ---
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }

# Flutter embedding Play Core (deferred components / split install) класстарына
# сілтейді, бірақ біз оны тәуелділік ретінде қоспаймыз — R8 «Missing class»
# қатесін бермеуі үшін ескерту өшіріледі (белгілі Flutter+R8 жағдайы).
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# --- flutter_local_notifications (GSON арқылы жоспарланған хабарламалар) ---
-keep class com.dexterous.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses,EnclosingMethod

# --- Firebase Cloud Messaging ---
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Модельдерде рефлексиямен оқылатын enum-дарды сақтау (жалпы қорғаныс).
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
