#!/usr/bin/env bash
set -e
T=/tmp/zapi_tpl
rm -rf "$T"
flutter create "$T" --platforms=android --org com.zapi --project-name zapi > /dev/null
cd android
cp "$T/android/gradle/wrapper/gradle-wrapper.properties" gradle/wrapper/gradle-wrapper.properties
TS="$T/android/settings.gradle.kts"
AGP=$(grep "com.android.application" "$TS" | grep -oE 'version "[^"]+"' | grep -oE '[0-9][^"]*' || true)
KT=$(grep "org.jetbrains.kotlin.android" "$TS" | grep -oE 'version "[^"]+"' | grep -oE '[0-9][^"]*' || true)
echo "AGP=$AGP KOTLIN=$KT"
if [ -n "$AGP" ]; then sed -i -E "s/(com.android.application\"\) version \")[^\"]+/\1$AGP/" settings.gradle.kts; fi
if [ -n "$KT" ]; then sed -i -E "s/(org.jetbrains.kotlin.android\"\) version \")[^\"]+/\1$KT/" settings.gradle.kts; fi
sed -i "s/compileSdk = 35/compileSdk = flutter.compileSdkVersion/; s/targetSdk = 35/targetSdk = flutter.targetSdkVersion/" app/build.gradle.kts
sed -i "/kotlinOptions {/,/^    }/d" app/build.gradle.kts
sed -i "/android.enableJetifier/d" gradle.properties
grep distributionUrl gradle/wrapper/gradle-wrapper.properties
