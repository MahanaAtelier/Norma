#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
manifest = root / 'android/app/src/main/AndroidManifest.xml'
text = manifest.read_text(encoding='utf-8')
required = {
    'PRÍDEL label': 'android:label="PRÍDEL"',
    'backup disabled': 'android:allowBackup="false"',
    'cleartext disabled': 'android:usesCleartextTraffic="false"',
}
for label, needle in required.items():
    if needle not in text:
        raise SystemExit(f'Android verification failed: {label}')
if (root / 'android/app/src/main/kotlin').exists() is False:
    raise SystemExit('Android verification failed: missing Kotlin source folder')

gradle = (root / 'android/app/build.gradle.kts').read_text(encoding='utf-8')
for label, needle in {
    'release signing properties': 'val keystoreProperties = Properties()',
    'release signing config': 'create("release")',
    'release build uses release key': 'signingConfig = signingConfigs.getByName("release")',
}.items():
    if needle not in gradle:
        raise SystemExit(f'Android verification failed: {label}')
print('Android project verification OK')
