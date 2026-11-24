"""Drive the release APK via Android's real file picker and capture playback UI.

The fixture is synthetic and stays on the disposable emulator. No test-only
entry point, network stream, private user file, or production code bypass.
"""
import re
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

APK_PACKAGE = 'com.omniplayer.app.omni_player'
NAME = 'omni-smoke-video.mp4'

def adb(*args, timeout=35):
    return subprocess.check_output(['adb', *args], timeout=timeout)

def xml():
    adb('shell', 'uiautomator', 'dump', '/sdcard/omni-window.xml', timeout=25)
    return ET.fromstring(adb('exec-out', 'cat', '/sdcard/omni-window.xml'))

def locate(names, seconds=35, optional=False):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            root = xml()
            for node in root.iter('node'):
                strings = [node.get('text',''), node.get('content-desc','')]
                if any(value == name or name in value.split('\\n') for value in strings for name in names):
                    nums = re.findall(r'\\d+', node.get('bounds',''))
                    if len(nums) == 4:
                        x1,y1,x2,y2 = map(int,nums)
                        if x2>x1 and y2>y1:
                            return ((x1+x2)//2,(y1+y2)//2)
        except (subprocess.SubprocessError, ET.ParseError):
            pass
        time.sleep(1)
    if optional:
        return None
    raise RuntimeError(f'UI element not found: {names}')

def tap(point):
    adb('shell','input','tap',str(point[0]),str(point[1]))
    time.sleep(1)

def click(*names, seconds=35, optional=False):
    point=locate(names,seconds,optional)
    if point is not None:
        tap(point)
        return True
    return False

def capture(path, landscape):
    data=adb('exec-out','screencap','-p')
    assert data[:8]==b'\\x89PNG\\r\\n\\x1a\\n'
    width,height=struct.unpack('>II',data[16:24])
    assert (width>height)==landscape, (path,width,height)
    with open(path,'wb') as out:
        out.write(data)
    print(f'Captured {path}: {width} x {height}',flush=True)

def main():
    adb('shell','mkdir','-p','/sdcard/Download')
    adb('push',sys.argv[1],f'/sdcard/Download/{NAME}',timeout=60)
    try:
        adb('shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE','-d',f'file:///sdcard/Download/{NAME}')
    except subprocess.SubprocessError:
        pass
    adb('shell','settings','put','system','accelerometer_rotation','0')
    adb('shell','settings','put','system','user_rotation','0')
    click('打开文件','Open files')
    # Recent documents can contain the test file after media scanning. If not,
    # use the system Downloads root. Multi-select picker may require Open.
    if not click(NAME,seconds=8,optional=True):
        click('Show roots','Open navigation drawer','显示根目录','打开导航抽屉','Show navigation drawer')
        click('Downloads','下载内容','下载')
        click(NAME)
    # Some DocumentsUI implementations return immediately; others need Open.
    if not locate(('暂停','Pause'),seconds=12,optional=True):
        click('Open','打开','Select','选择',seconds=10,optional=True)
    click('暂停','Pause',seconds=45)
    locate((NAME,),seconds=20)
    locate(('播放','Play'),seconds=15)
    capture('android-portrait-playing.png',False)
    click('全屏（手机横屏）','Fullscreen')
    locate(('退出全屏','Exit fullscreen'),seconds=35)
    capture('android-landscape-playing.png',True)
    click('锁定控件','Lock controls')
    locate(('解除锁定','Unlock controls'),seconds=20)
    capture('android-landscape-locked.png',True)
    click('解除锁定','Unlock controls')
    click('退出全屏','Exit fullscreen')
    locate((NAME,),seconds=35)
    print('Real local video: portrait, landscape, lock/unlock and exit passed.',flush=True)

if __name__=='__main__':
    try:
        main()
    except Exception:
        try:
            with open('android-playback-failure.png','wb') as out:
                out.write(adb('exec-out','screencap','-p'))
            print(adb('shell','dumpsys','activity','activities').decode(errors='replace')[-12000:])
        except Exception:
            pass
        raise
