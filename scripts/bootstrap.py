"""Create Flutter platform runners without replacing application code."""
import argparse
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
platforms = ('android', 'ios', 'web', 'windows', 'macos', 'linux')
parser = argparse.ArgumentParser()
parser.add_argument('--platform', choices=platforms)
args = parser.parse_args()
selected = (args.platform,) if args.platform else platforms
missing = [p for p in selected if not (root / p).exists()]
flutter = shutil.which('flutter')
if not flutter:
    raise SystemExit('Flutter must be on PATH.')
if missing:
    with tempfile.TemporaryDirectory() as temp:
        target = Path(temp) / 'omni_player'
        subprocess.run([flutter, 'create', '--no-pub', '--project-name', 'omni_player',
                        '--org', 'com.omniplayer.app', '--platforms=' + ','.join(missing),
                        str(target)], check=True)
        for name in missing:
            shutil.copytree(target / name, root / name)
        if not (root / '.metadata').exists():
            shutil.copy2(target / '.metadata', root / '.metadata')
if 'android' in selected:
    manifest = root / 'android/app/src/main/AndroidManifest.xml'
    text = manifest.read_text(encoding='utf-8')
    if 'android.permission.INTERNET' not in text:
        text = text.replace('<application', '<uses-permission android:name="android.permission.INTERNET" />\n    <application', 1)
        manifest.write_text(text, encoding='utf-8')
    text = manifest.read_text(encoding='utf-8')
    if 'android:label="omni_player"' in text:
        manifest.write_text(text.replace('android:label="omni_player"', 'android:label="Omni Player"'), encoding='utf-8')
    # Install the Omni launcher icon, including a pre-26 fallback and adaptive icon.
    res = root / 'android/app/src/main/res'
    icon_source = root / 'packaging/android'
    for source, destination in (
        ('omni_launcher.xml', 'mipmap-anydpi/omni_launcher.xml'),
        ('omni_launcher_foreground.xml', 'drawable/omni_launcher_foreground.xml'),
        ('omni_launcher_adaptive.xml', 'mipmap-anydpi-v26/omni_launcher.xml'),
        ('omni_launcher_colors.xml', 'values/omni_launcher_colors.xml'),
    ):
        out = res / destination
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(icon_source / source, out)
    text = manifest.read_text(encoding='utf-8')
    text = text.replace('@mipmap/ic_launcher', '@mipmap/omni_launcher')
    manifest.write_text(text, encoding='utf-8')
    # Install the Android PiP bridge into the generated launcher activity.
    activity = next((root / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))
    package_line = activity.read_text(encoding='utf-8').splitlines()[0]
    template = (root / 'packaging/android/MainActivity.kt.template').read_text(encoding='utf-8')
    activity.write_text(template.replace('@PACKAGE@', package_line), encoding='utf-8')
    text = manifest.read_text(encoding='utf-8')
    if 'android:supportsPictureInPicture=' not in text:
        text = text.replace('<activity', '<activity android:supportsPictureInPicture="true"', 1)
        manifest.write_text(text, encoding='utf-8')
if 'macos' in selected:
    for filename in ('DebugProfile.entitlements', 'Release.entitlements'):
        path = root / 'macos/Runner' / filename
        with path.open('rb') as handle:
            config = plistlib.load(handle)
        config['com.apple.security.network.client'] = True
        config.pop('com.apple.security.files.user-selected.read-only', None)
        config['com.apple.security.files.user-selected.read-write'] = True
        with path.open('wb') as handle:
            plistlib.dump(config, handle)
subprocess.run([flutter, 'pub', 'get'], cwd=root, check=True)
print('Platform runners are ready: ' + ', '.join(selected))
