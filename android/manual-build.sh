#!/bin/bash
# Manual APK pipeline used for the first shipped build (see README-ANDROID.md).
# aapt2 (resources) + kotlinc (code) + d8 (dex) + zipalign + apksigner.
set -u
export JAVA_HOME=$HOME/jdk
export PATH=$HOME/jdk/bin:$PATH
PROJ=$HOME/workspace/nightjar-hack-android
DEPS=$HOME/dl/deps
OUT=$HOME/dl/build
BT=$HOME/android-sdk/build-tools/34.0.0
ANDROID_JAR=$HOME/android-sdk/platforms/android-34/android.jar
rm -rf "$OUT"
mkdir -p "$OUT/res-compiled" "$OUT/gen" "$OUT/classes" "$OUT/dex"

# --- classpath jars: drop KMP metadata twins (plain artifact when an
# -android/-jvm sibling carries the real classes) ---
JARS=""
for jar in "$DEPS"/libs/*.jar; do
    case "$jar" in
        *lifecycle-common-java8*) continue ;;
    esac
    base=$(basename "$jar" .jar)
    stem=${base%--*}
    skip=0
    for suffix in android jvm; do
        if ls "$DEPS"/libs/${stem}-${suffix}--*.jar >/dev/null 2>&1; then
            skip=1
        fi
    done
    [ "$skip" = "1" ] && continue
    JARS="$JARS:$jar"
done
JARS=${JARS#:}
echo "classpath jars: $(echo "$JARS" | tr ':' '\n' | wc -l)"

# --- resources: app res + every AAR res tree ---
"$BT/aapt2" compile --dir "$PROJ/app/src/main/res" -o "$OUT/res-compiled/app.zip" || exit 1
FLATS="$OUT/res-compiled/app.zip"
EXTRA_PACKAGES=""
for aar in "$DEPS"/aars/*/; do
    name=$(basename "$aar")
    stem=${name%--*}
    skip=0
    for suffix in android jvm; do
        if ls -d "$DEPS"/aars/${stem}-${suffix}--*/ >/dev/null 2>&1; then
            skip=1
        fi
    done
    [ "$skip" = "1" ] && continue
    if [ -d "$aar/res" ] && [ -n "$(ls -A "$aar/res" 2>/dev/null)" ]; then
        if "$BT/aapt2" compile --dir "$aar/res" -o "$OUT/res-compiled/$name.zip" 2>"$OUT/aapt2-$name.log"; then
            FLATS="$FLATS $OUT/res-compiled/$name.zip"
        else
            echo "aapt2 compile FAILED for $name (see log)"
        fi
    fi
    pkg=$(grep -o 'package="[^"]*"' "$aar/AndroidManifest.xml" 2>/dev/null | head -1 | sed 's/package="//; s/"//')
    [ -n "$pkg" ] && EXTRA_PACKAGES="$EXTRA_PACKAGES --extra-packages $pkg"
done

"$BT/aapt2" link \
    -I "$ANDROID_JAR" \
    --manifest "$PROJ/app/src/main/AndroidManifest.xml" \
    --java "$OUT/gen" \
    --auto-add-overlay \
    $EXTRA_PACKAGES \
    -o "$OUT/base.apk" \
    $FLATS || exit 1
echo "aapt2 link OK"

# --- kotlin compile (app sources + generated R) ---
R_SOURCES=$(find "$OUT/gen" -name "*.java")
java -cp "$HOME/dl/kotlin-compiler-embeddable.jar:$DEPS/libs/org.jetbrains.kotlin--kotlin-stdlib--2.0.20.jar:$DEPS/libs/org.jetbrains.kotlinx--kotlinx-coroutines-core-jvm--1.8.1.jar:$DEPS/libs/org.jetbrains--annotations--13.0.jar:$HOME/dl/trove4j.jar" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler \
    -classpath "$JARS:$ANDROID_JAR" \
    -Xplugin="$HOME/dl/compose-plugin-embeddable.jar" \
    -jvm-target 17 \
    -no-stdlib -no-reflect \
    -d "$OUT/classes" \
    $(find "$PROJ/app/src/main/java" -name "*.kt") $R_SOURCES || exit 1
echo "kotlinc OK"

# --- generated R classes: kotlinc reads .java sources for symbols
# but emits no bytecode for them; library code (e.g. Compose's
# PoolingContainer) dereferences its own R at runtime, so compile
# every generated R.java with javac, as AGP does ---
"$JAVA_HOME/bin/javac" -encoding UTF-8 -cp "$ANDROID_JAR" \
    -d "$OUT/classes" $(find "$OUT/gen" -name "*.java") || exit 1
echo "javac R OK"

# --- dex ---
(cd "$OUT/classes" && "$JAVA_HOME/bin/jar" cf "$OUT/classes.jar" .) || exit 1
"$BT/d8" --min-api 26 --lib "$ANDROID_JAR" \
    --output "$OUT/dex" \
    "$OUT/classes.jar" $(echo "$JARS" | tr ':' ' ') || exit 1
echo "d8 OK"

# --- package ---
cp "$OUT/base.apk" "$OUT/app-unsigned.apk"
cd "$OUT"
mkdir -p staging/assets
cp "$PROJ"/app/src/main/assets/* staging/assets/ 2>/dev/null
for aar in "$DEPS"/aars/*/; do
    if [ -d "$aar/assets" ]; then
        cp -r "$aar/assets/." staging/assets/ 2>/dev/null
    fi
done
cp "$OUT"/dex/*.dex staging/
cd staging
zip -q -r "$OUT/app-unsigned.apk" classes*.dex assets
cd "$OUT"
"$BT/zipalign" -f -p 4 "$OUT/app-unsigned.apk" "$OUT/app-aligned.apk" || exit 1
if [ ! -f "$HOME/dl/debug.keystore" ]; then
    keytool -genkeypair -keystore "$HOME/dl/debug.keystore" \
        -storepass android -keypass android -alias androiddebugkey \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US" || exit 1
fi
"$BT/apksigner" sign \
    --ks "$HOME/dl/debug.keystore" --ks-pass pass:android \
    --key-pass pass:android \
    --out "$OUT/nightjar-hack.apk" "$OUT/app-aligned.apk" || exit 1
"$BT/apksigner" verify --print-certs "$OUT/nightjar-hack.apk" | head -3
ls -la "$OUT/nightjar-hack.apk"
echo "BUILD DONE"
