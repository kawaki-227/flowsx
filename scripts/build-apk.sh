#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import os,re,sys
p=os.environ['PACKAGE_ID']; v=os.environ['APP_VERSION']; n=os.environ['APP_NAME']; t=os.environ['SOURCE_TYPE']; u=os.environ['SOURCE_URL']
if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+',p) or len(p)>180: raise SystemExit('Invalid package id')
if not re.fullmatch(r'\d+\.\d+\.\d+',v): raise SystemExit('Invalid version')
if t not in ('link','html','zip'): raise SystemExit('Invalid source type')
if not u.startswith(('https://','http://')): raise SystemExit('Source must be HTTP(S)')
open('/tmp/flowsx_meta','w').write(n.replace('\n',' ')+'\n'+p+'\n'+v+'\n'+t+'\n'+u+'\n'+os.environ['INTERNET'])
PY
mapfile -t META < /tmp/flowsx_meta
APP_NAME="${META[0]}"; PACKAGE_ID="${META[1]}"; APP_VERSION="${META[2]}"; SOURCE_TYPE="${META[3]}"; SOURCE_URL="${META[4]}"; INTERNET="${META[5]}"
mkdir -p android/app/src/main/java/$(echo "$PACKAGE_ID" | tr . /) android/app/src/main/assets
if [[ "$SOURCE_TYPE" == "link" ]]; then
  # URL is embedded as the start page. Android WebView uses a remote site.
  START_URL="$SOURCE_URL"
  printf '%s\n' '<!doctype html><meta charset="utf-8"><title>FlowsX</title><p>Cette application ouvre le site configuré.</p>' > android/app/src/main/assets/index.html
else
  curl --fail --location --silent --show-error --max-time 90 "$SOURCE_URL" -o /tmp/source
  if [[ "$SOURCE_TYPE" == "html" ]]; then
    cp /tmp/source android/app/src/main/assets/index.html
  else
    python3 - <<'PY'
import zipfile,os,sys
p='/tmp/source'; dest='android/app/src/main/assets/site'
with zipfile.ZipFile(p) as z:
  names=z.namelist()
  if len(names)>4000: raise SystemExit('ZIP contains too many entries')
  total=0
  for i in z.infolist():
    if i.is_dir(): continue
    name=i.filename.replace('\\','/')
    if name.startswith('/') or '..' in name.split('/') or len(name)>240: raise SystemExit('Unsafe ZIP path')
    total+=i.file_size
    if total>150*1024*1024: raise SystemExit('Expanded ZIP exceeds 150 MiB')
  z.extractall(dest)
if not os.path.isfile(dest+'/index.html'): raise SystemExit('ZIP must contain index.html at its root')
PY
    # Android asset loader serves local files from assets/site.
    mkdir -p android/app/src/main/assets
  fi
  START_URL="file:///android_asset/index.html"
fi
mkdir -p android/app/src/main
cat > android/settings.gradle <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
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
cat > android/app/build.gradle <<EOF
plugins { id 'com.android.application' }
android {
  namespace '${PACKAGE_ID}'
  compileSdk 35
  defaultConfig {
    applicationId '${PACKAGE_ID}'
    minSdk 23
    targetSdk 28
    versionCode ${APP_VERSION%%.*}
    versionName '${APP_VERSION}'
  }
}
EOF
JAVA_DIR="android/app/src/main/java/$(echo "$PACKAGE_ID" | tr . /)"
cat > android/app/src/main/AndroidManifest.xml <<EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  $(if [[ "$INTERNET" == "true" ]]; then echo '<uses-permission android:name="android.permission.INTERNET" />'; fi)
  <application android:theme="@android:style/Theme.Material.Light.NoActionBar" android:label="$(printf '%s' "$APP_NAME" | sed 's/[&<>"]/ /g')" android:usesCleartextTraffic="false" android:allowBackup="false">
    <activity android:name=".MainActivity" android:exported="true" android:configChanges="orientation|screenSize|keyboardHidden">
      <intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
    </activity>
  </application>
</manifest>
EOF
cat > "$JAVA_DIR/MainActivity.java" <<EOF
package ${PACKAGE_ID};
import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebSettings;
public class MainActivity extends Activity {
 @Override public void onCreate(Bundle b) {
  super.onCreate(b);
  WebView w=new WebView(this); setContentView(w);
  WebSettings s=w.getSettings(); s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true);
  w.setWebViewClient(new WebViewClient());
  w.loadUrl("${START_URL}");
 }
 @Override public void onBackPressed(){ setContentView(getWindow().getDecorView()); super.onBackPressed(); }
}
EOF
