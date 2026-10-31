"""Check Quiet against a running tool/pomo_resource_profile.dart profile build.

Usage: python3 tool/pomo/check_quiet.py HTTP_VM_URI OUTPUT_DIRECTORY
The fixture uses temporary guest data. Captures read the existing render target
before forcing a reference redraw, so a stale static pose cannot pass unnoticed.
"""
import base64
import hashlib
import json
import sys
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen


def main():
    uri, output = sys.argv[1], Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)

    def rpc(method, **params):
        with urlopen(f'{uri.rstrip("/")}/{method}?{urlencode(params)}', timeout=60) as response:
            result = json.load(response)
        assert 'error' not in result, result
        return result['result']

    isolate = next(i['id'] for i in rpc('getVM')['isolates'] if i['name'] == 'main')

    def control(**params):
        status = rpc('ext.pomodoist.resourceProfile', isolateId=isolate,
                     **{k: str(v).lower() if isinstance(v, bool) else v for k, v in params.items()})
        status.pop('frames', None)
        assert status['error'] is None and not status['flutterErrors'], status
        return status

    def wait_for(predicate):
        deadline = time.monotonic() + 30
        while True:
            status = control()
            if predicate(status):
                return status
            assert time.monotonic() < deadline, status
            time.sleep(.05)

    def quiet():
        before = control()
        assert not before['animated'] and before['nativeScheduler']['paused'], before
        time.sleep(1)
        after = control()
        assert after['nativeScheduler']['scheduledFrames'] == before['nativeScheduler']['scheduledFrames'], after

    def animated():
        before = control(capture=True, renderCapture=False)
        image = before.pop('capture')['rgba']
        time.sleep(2)
        after = control(capture=True, renderCapture=False)
        assert after.pop('capture')['rgba'] != image, 'Animation image did not change'
        delta = after['nativeScheduler']['scheduledFrames'] - before['nativeScheduler']['scheduledFrames']
        assert after['animated'] and not after['nativeScheduler']['paused'] and delta >= 30, after
        return delta

    report = {'captures': [], 'resume_frames': []}
    try:
        # Isolate Quiet from the separately tracked hidden -> inactive engine bug.
        control(mode='animated', testLifecycle='resumed')
        wait_for(lambda s: s['widgets']['Texture'] > 0)
        report['resume_frames'].append(animated())
        control(mode='static')
        quiet()
        control(testLifecycle='inactive')
        quiet()
        control(mode='animated')
        report['resume_frames'].append(animated())
        control(mode='static')
        control(testLifecycle='hidden')
        control(testLifecycle='resumed')
        quiet()
        for scale in [1, 2.5]:
            control(mode='static', scale=scale)
            hashes = set()
            for pose in ['calm', 'focus', 'rest', 'tired', 'greeting', 'happy', 'sad', 'surprised']:
                status = control(pose=pose, capture=True, renderCapture=False)
                assert status['emotion'] == pose and not status['animated'], status
                capture = status['capture']
                pixels = base64.b64decode(capture['rgba'])
                size = (capture['width'], capture['height'])
                assert len(pixels) == size[0] * size[1] * 4, size
                assert min(pixels[3::4]) == 0 and max(pixels[3::4]) > 0, pose
                reference = control(capture=True)['capture']
                delta = [abs(a - b) for a, b in zip(pixels, base64.b64decode(reference['rgba']))]
                # Compare aggregate error: native edge rounding varies between redraws.
                mean_delta = sum(delta) / len(delta)
                rms_delta = (sum(d * d for d in delta) / len(delta)) ** .5
                assert mean_delta <= .001 and rms_delta <= .1, (
                    f'Stale static render: {pose}, {scale}; mean={mean_delta}, rms={rms_delta}')
                digest = hashlib.sha256(pixels).hexdigest()
                hashes.add(digest)
                report['captures'].append({'pose': pose, 'scale': scale, 'size': size,
                                           'sha256': digest, 'max_channel_delta': max(delta),
                                           'mean_channel_delta': mean_delta, 'rms_channel_delta': rms_delta})
            assert len(hashes) >= 6, 'Static poses did not change'
            quiet()
        assert report['captures'][0]['size'] != report['captures'][8]['size'], 'Resize did not reach render target'
        control(mode='animated', reduceMotion=True)
        quiet()
        for mode in ['animated', 'static', 'animated']:
            control(mode='hidden')
            wait_for(lambda s: not s['engineAlive'])
            control(mode=mode, testLifecycle='resumed')
            wait_for(lambda s: s['widgets']['Texture'] > 0)
            if mode == 'animated':
                report['resume_frames'].append(animated())
            else:
                quiet()
            control(mode='static' if mode == 'animated' else 'animated')
            if mode == 'animated':
                quiet()
            else:
                report['resume_frames'].append(animated())
        report['passed'] = True
    finally:
        control(mode='hidden')
        report['final_status'] = wait_for(lambda s: not s['engineAlive'])
        (output / 'checks.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
