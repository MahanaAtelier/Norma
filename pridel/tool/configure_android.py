#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
manifest = root / 'android/app/src/main/AndroidManifest.xml'
if not manifest.exists():
    raise SystemExit(f'Missing {manifest}')
text = manifest.read_text(encoding='utf-8')

app_match = re.search(r'<application\b[^>]*>', text, flags=re.S)
if not app_match:
    raise SystemExit('AndroidManifest.xml has no <application> tag')
app = app_match.group(0)

def set_attr(tag: str, name: str, value: str) -> str:
    pattern = rf'\s{name}="[^"]*"'
    if re.search(pattern, tag):
        return re.sub(pattern, f' {name}="{value}"', tag)
    return tag[:-1] + f' {name}="{value}">'

app = set_attr(app, 'android:label', 'PRÍDEL')
app = set_attr(app, 'android:allowBackup', 'false')
app = set_attr(app, 'android:usesCleartextTraffic', 'false')
text = text[:app_match.start()] + app + text[app_match.end():]
manifest.write_text(text, encoding='utf-8')

# Release signing configuration. Secrets are supplied at build time through
# android/key.properties and android/app/pridel-release.jks; neither is committed.
gradle = root / 'android/app/build.gradle.kts'
if not gradle.exists():
    raise SystemExit(f'Missing {gradle}')
g = gradle.read_text(encoding='utf-8')

imports = 'import java.io.FileInputStream\nimport java.util.Properties\n\n'
if 'import java.util.Properties' not in g:
    g = imports + g

props = '''val keystoreProperties = Properties()\nval keystorePropertiesFile = rootProject.file("key.properties")\nif (keystorePropertiesFile.exists()) {\n    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n}\n\n'''
if 'val keystoreProperties = Properties()' not in g:
    marker = 'android {\n'
    if marker not in g:
        raise SystemExit('Unable to find android block in build.gradle.kts')
    g = g.replace(marker, props + marker, 1)

signing = '''    signingConfigs {\n        create("release") {\n            if (keystorePropertiesFile.exists()) {\n                keyAlias = keystoreProperties["keyAlias"] as String\n                keyPassword = keystoreProperties["keyPassword"] as String\n                storeFile = file(keystoreProperties["storeFile"] as String)\n                storePassword = keystoreProperties["storePassword"] as String\n            }\n        }\n    }\n\n'''
if 'create("release")' not in g:
    marker = '    buildTypes {\n'
    if marker not in g:
        raise SystemExit('Unable to find buildTypes block in build.gradle.kts')
    g = g.replace(marker, signing + marker, 1)

g = g.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("release")')
gradle.write_text(g, encoding='utf-8')

# Secret signing files must never be committed.
gitignore = root / '.gitignore'
gi = gitignore.read_text(encoding='utf-8') if gitignore.exists() else ''
for line in ['android/key.properties', 'android/app/*.jks', 'android/app/*.keystore']:
    if line not in gi.splitlines():
        gi += ('\n' if gi and not gi.endswith('\n') else '') + line + '\n'
gitignore.write_text(gi, encoding='utf-8')

required = [
    'android:label="PRÍDEL"',
    'android:allowBackup="false"',
    'android:usesCleartextTraffic="false"',
]
check = manifest.read_text(encoding='utf-8')
missing = [item for item in required if item not in check]
if missing:
    raise SystemExit('Manifest verification failed: ' + ', '.join(missing))
print('Android manifest and release signing configured and verified.')
