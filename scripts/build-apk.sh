#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# FlowsX - Préparation du projet Android
# ============================================================

python3 - <<'PY'
import os
import re
import sys

p = os.environ["PACKAGE_ID"]
v = os.environ["APP_VERSION"]
n = os.environ["APP_NAME"]
t = os.environ["SOURCE_TYPE"]
u = os.environ["SOURCE_URL"]

# Vérification du package Android
if not re.fullmatch(
    r"[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+",
    p
) or len(p) > 180:
    raise SystemExit("❌ Package Android invalide")

# Vérification de la version
if not re.fullmatch(r"\d+\.\d+\.\d+", v):
    raise SystemExit("❌ Version invalide. Exemple : 1.0.0")

# Vérification du type de source
if t not in ("link", "html", "zip"):
    raise SystemExit("❌ Source type invalide. Utiliser : link, html ou zip")

# Vérification de l'URL
if not u.startswith(("https://", "http://")):
    raise SystemExit("❌ La source doit être une URL HTTP(S)")

# Calcul d'un versionCode Android valide
major, minor, patch = map(int, v.split("."))

# Toujours >= 1
version_code = max(
    1,
    major * 10000 +
    minor * 100 +
    patch
)

with open("/tmp/flowsx_meta", "w", encoding="utf-8") as f:
    f.write(n.replace("\n", " ") + "\n")
    f.write(p + "\n")
    f.write(v + "\n")
    f.write(t + "\n")
    f.write(u + "\n")
    f.write(os.environ["INTERNET"] + "\n")
    f.write(str(version_code) + "\n")
PY

mapfile -t META < /tmp/flowsx_meta

APP_NAME="${META[0]}"
PACKAGE_ID="${META[1]}"
APP_VERSION="${META[2]}"
SOURCE_TYPE="${META[3]}"
SOURCE_URL="${META[4]}"
INTERNET="${META[5]}"
VERSION_CODE="${META[6]}"

PACKAGE_PATH="$(echo "$PACKAGE_ID" | tr '.' '/')"
JAVA_DIR="android/app/src/main/java/$PACKAGE_PATH"
ASSETS_DIR="android/app/src/main/assets"

mkdir -p "$JAVA_DIR"
mkdir -p "$ASSETS_DIR"

# ============================================================
# Préparation de la source
# ============================================================

if [[ "$SOURCE_TYPE" == "link" ]]; then

    # Site distant
    START_URL="$SOURCE_URL"

    cat > "$ASSETS_DIR/index.html" <<'EOF'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>FlowsX</title>
</head>
<body>
  <p>Chargement du site…</p>
</body>
</html>
EOF

elif [[ "$SOURCE_TYPE" == "html" ]]; then

    echo "⬇️ Téléchargement du fichier HTML..."

    curl \
      --fail \
      --location \
      --silent \
      --show-error \
      --max-time 90 \
      "$SOURCE_URL" \
      -o /tmp/source

    cp /tmp/source "$ASSETS_DIR/index.html"

    START_URL="file:///android_asset/index.html"

elif [[ "$SOURCE_TYPE" == "zip" ]]; then

    echo "⬇️ Téléchargement du ZIP..."

    curl \
      --fail \
      --location \
      --silent \
      --show-error \
      --max-time 90 \
      "$SOURCE_URL" \
      -o /tmp/source.zip

    rm -rf "$ASSETS_DIR/site"
    mkdir -p "$ASSETS_DIR/site"

    echo "📦 Vérification et extraction du ZIP..."

    python3 - <<'PY'
import os
import zipfile
import sys

source = "/tmp/source.zip"
dest = "android/app/src/main/assets/site"

with zipfile.ZipFile(source) as z:

    names = z.namelist()

    # Limite du nombre de fichiers
    if len(names) > 4000:
        raise SystemExit("❌ ZIP contient trop de fichiers")

    total = 0
    has_index = False

    for info in z.infolist():

        if info.is_dir():
            continue

        name = info.filename.replace("\\", "/")

        # Protection contre les chemins dangereux
        if name.startswith("/"):
            raise SystemExit(f"❌ Chemin ZIP dangereux : {name}")

        parts = name.split("/")

        if ".." in parts:
            raise SystemExit(f"❌ Chemin ZIP dangereux : {name}")

        if len(name) > 240:
            raise SystemExit(f"❌ Nom de fichier trop long : {name}")

        total += info.file_size

        # Limite de taille décompressée
        if total > 150 * 1024 * 1024:
            raise SystemExit(
                "❌ Le ZIP dépasse la limite de 150 MiB décompressés"
            )

        if name == "index.html":
            has_index = True

    if not has_index:
        raise SystemExit(
            "❌ Le ZIP doit contenir index.html à sa racine"
        )

    z.extractall(dest)

print("✅ ZIP extrait correctement")
PY

    # Le site est maintenant dans :
    # android/app/src/main/assets/site/
    #
    # On charge index.html depuis ce dossier.
    START_URL="file:///android_asset/site/index.html"

fi

# ============================================================
# Création du projet Gradle Android
# ============================================================

mkdir -p android/app/src/main

cat > android/settings.gradle <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)

    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "FlowsXBuild"

include(":app")
EOF

cat > android/build.gradle <<'EOF'
plugins {
    id 'com.android.application' version '8.7.3' apply false
}
EOF

cat > android/gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
android.useAndroidX=true
EOF

# ============================================================
# Build Android
# ============================================================

cat > android/app/build.gradle <<EOF
plugins {
    id 'com.android.application'
}

android {
    namespace '${PACKAGE_ID}'
    compileSdk 35

    defaultConfig {
        applicationId '${PACKAGE_ID}'
        minSdk 23
        targetSdk 28

        versionCode ${VERSION_CODE}
        versionName '${APP_VERSION}'
    }
}
EOF

# ============================================================
# AndroidManifest.xml
# ============================================================

if [[ "$INTERNET" == "true" ]]; then
    INTERNET_PERMISSION='<uses-permission android:name="android.permission.INTERNET" />'
else
    INTERNET_PERMISSION=''
fi

cat > android/app/src/main/AndroidManifest.xml <<EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    ${INTERNET_PERMISSION}

    <application
        android:theme="@android:style/Theme.Material.Light.NoActionBar"
        android:label="${APP_NAME}"
        android:usesCleartextTraffic="true"
        android:allowBackup="false"
        android:supportsRtl="true">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|keyboardHidden">

            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>

        </activity>

    </application>

</manifest>
EOF

# ============================================================
# MainActivity.java
# ============================================================

cat > "$JAVA_DIR/MainActivity.java" <<EOF
package ${PACKAGE_ID};

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class MainActivity extends Activity {

    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        webView = new WebView(this);

        setContentView(webView);

        WebSettings settings = webView.getSettings();

        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setDatabaseEnabled(true);

        webView.setWebViewClient(new WebViewClient());

        webView.loadUrl("${START_URL}");
    }

    @Override
    public void onBackPressed() {

        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
EOF

echo ""
echo "=============================================="
echo "✅ Projet Android préparé avec succès"
echo "=============================================="
echo "Application : $APP_NAME"
echo "Package     : $PACKAGE_ID"
echo "Version     : $APP_VERSION"
echo "VersionCode : $VERSION_CODE"
echo "Source      : $SOURCE_TYPE"
echo "URL         : $SOURCE_URL"
echo "Internet    : $INTERNET"
echo "=============================================="
