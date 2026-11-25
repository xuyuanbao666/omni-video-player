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


def locate(names, seconds=35, optional=False, clickable=False):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        remaining = max(1, deadline - time.monotonic())
        try:
            adb('shell', 'uiautomator', 'dump', '/sdcard/omni-window.xml',
                timeout=min(8, remaining))
            root = ET.fromstring(adb(
                'exec-out', 'cat', '/sdcard/omni-window.xml', timeout=min(5, remaining)
            ))
            for node in root.iter('node'):
                labels = node.get('text', '').splitlines() + node.get('content-desc', '').splitlines()
                if clickable and node.get('clickable') != 'true':
                    continue
                if not any(name in labels for name in names):
                    continue
                bounds = re.findall(r'\d+', node.get('bounds', ''))
                if len(bounds) == 4:
                    x1, y1, x2, y2 = map(int, bounds)
                    if x2 > x1 and y2 > y1:
                        return ((x1 + x2) // 2, (y1 + y2) // 2)
        except (subprocess.SubprocessError, ET.ParseError):
            # A transitioning window may not have an accessibility tree yet.
            adb('get-state', timeout=5)
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
    adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0')
    adb('shell', 'settings', 'put', 'system', 'user_rotation', '0')
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
    width, height = capture('landscape-playing.png', landscape=True)
    verify_video_frame(OUTPUT / 'landscape-playing.png', landscape=True)
    if not click(*LOCK, seconds=3, optional=True):
        tap((width // 2, height // 2))
        click(*LOCK, seconds=10)
    locate(UNLOCK, seconds=10)
    capture('landscape-locked.png', landscape=True)
    click(*UNLOCK, seconds=10)
    click(*EXIT_FULLSCREEN, seconds=10)
    locate(PLAYING, seconds=15)
    capture('portrait-restored.png', landscape=False)
    print('Local playback, landscape, lock/unlock and portrait restore passed.', flush=True)


if __name__ == '__main__':
    main(sys.argv[1])
