"""Drive the release APK through Android's file picker using a synthetic video."""

from pathlib import Path
import re
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

NAME = 'omni-smoke-video.mp4'
OUTPUT = Path('android-smoke')
PLAYING = ('暂停', 'Pause')
PLAY = ('播放', 'Play')
LOCK = ('锁定控件', 'Lock controls')
UNLOCK = ('解除锁定', 'Unlock controls')
EXIT_FULLSCREEN = ('退出全屏', 'Exit fullscreen')


def adb(*args, timeout=20):
    return subprocess.check_output(['adb', *args], timeout=timeout)


def node_labels(node):
    return node.get('text', '').splitlines() + node.get('content-desc', '').splitlines()


def node_center(node):
    bounds = re.findall(r'\d+', node.get('bounds', ''))
    if len(bounds) == 4:
        x1, y1, x2, y2 = map(int, bounds)
        if x2 > x1 and y2 > y1:
            return ((x1 + x2) // 2, (y1 + y2) // 2)
    return None


launcher_recoveries = 0


def recover_launcher_anr(nodes):
    global launcher_recoveries
    titles = [label for node in nodes for label in node_labels(node)
              if "isn't responding" in label or "keeps stopping" in label]
    if not titles:
        return False
    if titles != ["Pixel Launcher isn't responding"]:
        raise RuntimeError(f'Unexpected application failure dialog: {titles}')
    for node in nodes:
        if node.get('package') == 'android' and 'Close app' in node_labels(node):
            point = node_center(node)
            if point is None:
                continue
            if launcher_recoveries >= 2:
                raise RuntimeError('Repeated background Pixel Launcher ANR')
            launcher_recoveries += 1
            (OUTPUT / f'launcher-anr-{launcher_recoveries}.png').write_bytes(
                adb('exec-out', 'screencap', '-p'))
            print('Dismissing verified emulator Pixel Launcher ANR', flush=True)
            tap(point)
            return True
    raise RuntimeError('Pixel Launcher ANR identified but system close button unavailable')


def locate(names, seconds=35, optional=False, clickable=False):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        remaining = max(1, deadline - time.monotonic())
        try:
            adb('shell', 'rm', '-f', '/sdcard/omni-window.xml', timeout=min(5, remaining))
            result = adb('shell', 'uiautomator', 'dump', '/sdcard/omni-window.xml',
                         timeout=min(8, remaining))
            if b'ERROR' in result:
                time.sleep(0.5)
                continue
            xml = adb('exec-out', 'cat', '/sdcard/omni-window.xml',
                      timeout=min(5, remaining))
            (OUTPUT / 'last-window.xml').write_bytes(xml)
            root = ET.fromstring(xml)
            nodes = list(root.iter('node'))
            # A real failure screenshot identified the emulator's background
            # Pixel Launcher ANR over the already-rendered Omni home screen.
            # Recover only from this exact external system dialog, never from
            # a player ANR or any unknown application failure.
            if recover_launcher_anr(nodes):
                time.sleep(0.5)
                continue
            for node in nodes:
                if clickable and node.get('clickable') != 'true':
                    continue
                if not any(name in node_labels(node) for name in names):
                    continue
                point = node_center(node)
                if point is not None:
                    return point
        except (subprocess.SubprocessError, ET.ParseError):
            # A transitioning window may not have an accessibility tree yet.
            try:
                adb('get-state', timeout=5)
            except subprocess.SubprocessError:
                pass
        time.sleep(0.5)
    if not optional:
        raise RuntimeError(f'UI element not found: {names}')
    return None


def tap(point):
    adb('shell', 'input', 'tap', str(point[0]), str(point[1]))


def click(*names, seconds=35, optional=False, clickable=False):
    point = locate(names, seconds, optional, clickable)
    if point is not None:
        tap(point)
        return True
    return False


def png_size(data):
    if len(data) < 24 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise RuntimeError('ADB did not return a PNG screenshot')
    return struct.unpack('>II', data[16:24])


def capture(filename, landscape):
    deadline = time.monotonic() + 15
    while True:
        data = adb('exec-out', 'screencap', '-p')
        width, height = png_size(data)
        if (width > height) == landscape:
            (OUTPUT / filename).write_bytes(data)
            print(f'Captured {filename}: {width} x {height}', flush=True)
            return width, height
        if time.monotonic() >= deadline:
            raise RuntimeError(f'{filename}: unexpected orientation {width} x {height}')
        time.sleep(0.5)


def verify_video_frame(path, landscape):
    # The synthetic clip is saturated. Sample its interior away from UI overlays.
    area = 'crop=iw/3:ih/3' if landscape else 'crop=iw/3:ih/8:iw/3:ih/5'
    pixels = subprocess.check_output([
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', str(path),
        '-vf', f'{area},scale=16:16', '-frames:v', '1',
        '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1',
    ], timeout=15)
    saturated = sum(
        max(pixels[i:i + 3]) - min(pixels[i:i + 3]) > 65
        for i in range(0, len(pixels), 3)
    )
    if saturated < 20:
        raise RuntimeError(f'{path.name}: no visible synthetic video frame')


def main(fixture):
    OUTPUT.mkdir(exist_ok=True)
    print('Waiting for the player home screen', flush=True)
    locate(('打开文件', 'Open files'), seconds=75)
    capture('launch.png', landscape=False)

    print('Setting playback controls to stay visible', flush=True)
    click('更多', 'More')
    click('设置', 'Settings')
    click('播放', 'Playback')
    click('自动隐藏控制栏', 'Auto-hide controls')
    click('保存', 'Save')
    locate(('打开文件', 'Open files'), seconds=35)

    adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0')
    adb('shell', 'settings', 'put', 'system', 'user_rotation', '0')
    # Automatic rotation is not a promise to return to portrait. Select the
    # application's portrait preference explicitly before testing restoration.
    click('屏幕方向', 'Screen orientation')
    click('锁定竖屏', 'Portrait')
    locate(('打开文件', 'Open files'), seconds=35)
    capture('portrait-preferred.png', landscape=False)
    adb('shell', 'mkdir', '-p', '/sdcard/Download')
    adb('push', fixture, f'/sdcard/Download/{NAME}', timeout=60)
    adb('shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
        '-d', f'file:///sdcard/Download/{NAME}')

    print('Opening local video through the system picker', flush=True)
    click('打开文件', 'Open files')
    if not click(NAME, seconds=8, optional=True):
        click('Show roots', 'Open navigation drawer', '显示根目录', '打开导航抽屉',
              'Show navigation drawer')
        click('Downloads', '下载内容', '下载')
        click(NAME)
    click('Open', '打开', 'Select', '选择', seconds=5, optional=True)
    locate((NAME,), seconds=35)
    if locate(PLAYING, seconds=6, optional=True) is None:
        click(*PLAY, seconds=20, clickable=True)
    locate(PLAYING, seconds=35)
    time.sleep(2)
    capture('portrait-playing.png', landscape=False)
    verify_video_frame(OUTPUT / 'portrait-playing.png', landscape=False)

    click('全屏（手机横屏）', 'Fullscreen')
    capture('landscape-playing.png', landscape=True)
    verify_video_frame(OUTPUT / 'landscape-playing.png', landscape=True)
    click(*LOCK, seconds=45)
    locate(UNLOCK, seconds=25)
    capture('landscape-locked.png', landscape=True)
    click(*UNLOCK, seconds=25)
    click(*EXIT_FULLSCREEN, seconds=25)
    locate(PLAYING, seconds=35)
    locate(('打开文件', 'Open files'), seconds=35)
    capture('portrait-restored.png', landscape=False)
    verify_video_frame(OUTPUT / 'portrait-restored.png', landscape=False)
    print('Local playback, landscape, lock/unlock and portrait restore passed.', flush=True)


if __name__ == '__main__':
    main(sys.argv[1])
