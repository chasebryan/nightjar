# Standalone manual-build script for nightjar-hack Android (no Gradle).
# Manual APK pipeline for nightjar-hack-android:
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
# AAR-bundled runtime jars (AAR libs/*.jar) are part of the classpath too -
# AGP dexes them; skipping them loses e.g. emoji2's flatbuffer classes.
for bj in $(find "$DEPS/aars" -path "*/libs/*.jar"); do JARS="$JARS:$bj"; done
echo "classpath jars: $(echo "$JARS" | tr ':' '\n' | wc -l)"

# --- resources: app res + every AAR res tree ---
"$BT/aapt2" compile --dir "$PROJ/app/src/main/res" -o "$OUT/res-compiled/app.zip" || exit 1
FLATS="$OUT/res-compiled/app.zip"
EXTRA_PACKAGES=""
MERGE_DIRS=""
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
    MERGE_DIRS="$MERGE_DIRS $aar"
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

# --- manifest merge (AGP merges library manifests; without it, components the
# libraries declare - androidx.startup provider, profileinstaller receiver,
# lifecycle/emoji2 initializers - silently vanish from the APK) ---
python3 - "$PROJ/app/src/main/AndroidManifest.xml" "$OUT/AndroidManifest.xml" \
    "net.nosuchmachine.nightjarhack" $MERGE_DIRS <<'PYEOF' || exit 1
import sys
import xml.etree.ElementTree as ET
ANDROID = "http://schemas.android.com/apk/res/android"
TOOLS = "http://schemas.android.com/tools"
ET.register_namespace("android", ANDROID)
def an(n): return "{%s}%s" % (ANDROID, n)
app_path, out_path, pkg = sys.argv[1], sys.argv[2], sys.argv[3]
tree = ET.parse(app_path); root = tree.getroot()
app_el = root.find("application")
existing = {}
for child in app_el:
    nm = child.get(an("name"))
    if nm: existing[(child.tag, nm)] = child
merged, order = {}, []
for d in sys.argv[4:]:
    try: mroot = ET.parse(d.rstrip("/") + "/AndroidManifest.xml").getroot()
    except Exception: continue
    mapp = mroot.find("application")
    if mapp is None: continue
    for comp in mapp:
        if comp.tag not in ("provider", "receiver", "service", "activity",
                            "activity-alias", "uses-library"):
            continue
        nm = comp.get(an("name"))
        if not nm or (comp.tag, nm) in existing: continue
        key = (comp.tag, nm)
        if key in merged:
            base = merged[key]
            have = {c.get(an("name")) for c in base}
            for c in comp:
                if c.get(an("name")) not in have: base.append(c)
        else:
            merged[key] = comp; order.append(key)
for key in order: app_el.append(merged[key])
for el in root.iter():
    for k in list(el.attrib):
        if k.startswith("{%s}" % TOOLS): del el.attrib[k]
        elif "${applicationId}" in el.get(k):
            el.set(k, el.get(k).replace("${applicationId}", pkg))
tree.write(out_path, xml_declaration=True, encoding="utf-8")
print("manifest merged: %d library components" % len(order))
PYEOF

"$BT/aapt2" link \
    -I "$ANDROID_JAR" \
    --manifest "$OUT/AndroidManifest.xml" \
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
# --- dependency jar resources: AGP packages these into the APK (kotlin_builtins,
# .kotlin_module, and META-INF/services). Service files from several jars must
# be CONCATENATED, not overwritten - a missing services entry breaks runtime
# ServiceLoader lookups (coroutines dispatchers, exception handlers). ---
RESOUT="$OUT/jarres"; rm -rf "$RESOUT"; mkdir -p "$RESOUT/META-INF/services"
for jar in $(echo "$JARS" | tr ':' ' '); do
    (cd "$RESOUT" && unzip -qo "$jar" -x "*.class" "META-INF/*.SF" "META-INF/*.RSA" \
        "META-INF/*.DSA" "META-INF/MANIFEST.MF" "META-INF/AL2.0" "META-INF/LGPL2.1" \
        "META-INF/services/*" 2>/dev/null)
    for svc in $(jar tf "$jar" 2>/dev/null | grep "^META-INF/services/[^/]*$"); do
        unzip -p "$jar" "$svc" >> "$RESOUT/$svc.tmp" 2>/dev/null
        printf '\n' >> "$RESOUT/$svc.tmp"
    done
done
for t in "$RESOUT"/META-INF/services/*.tmp; do
    [ -f "$t" ] || continue
    sed '/^#/d; /^[[:space:]]*$/d' "$t" | sort -u > "${t%.tmp}"; rm -f "$t"
done
(cd "$RESOUT" && zip -q -r "$OUT/app-unsigned.apk" .)
echo "jar resources merged"
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
