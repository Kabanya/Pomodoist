"""Automated native Pomo pose captures and close/reopen regression checks.

Run against tool/pomo_resource_profile.dart after memory collection, in a fresh
process. Requires Pillow and NumPy, as does the existing model packer.
"""
import argparse
import base64
import json
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('uri')
    parser.add_argument('output', type=Path)
    parser.add_argument('--reference', type=Path)
    parser.add_argument('--model-file', type=Path, help='Generated app-bundle model for a temporary bad-asset fixture')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    def rpc(method, **params):
        with urlopen(f'{args.uri.rstrip("/")}/{method}?{urlencode(params)}', timeout=60) as response:
            result = json.load(response)
        if 'error' in result:
            raise RuntimeError(result['error'])
        return result['result']

    isolate = next(i['id'] for i in rpc('getVM')['isolates'] if i['name'] == 'main')

    def control(**params):
        return rpc('ext.pomodoist.resourceProfile', isolateId=isolate,
                   **{k: str(v).lower() if isinstance(v, bool) else v for k, v in params.items()})

    expected_errors = 0

    def wait_for(predicate):
        deadline = time.monotonic() + 30
        while True:
            status = control()
            assert status['error'] is None and len(status['flutterErrors']) == expected_errors, status
            if predicate(status):
                return status
            if time.monotonic() >= deadline:
                raise TimeoutError(status)
            time.sleep(.02)

    report = {'captures': [], 'rapid_cycles': [], 'load_close': {}}
    try:
        control(mode='animated')
        wait_for(lambda s: s['widgets']['Texture'] > 0)
        suspended = control(testLifecycle='hidden')
        assert suspended['lifecycleStopped'], suspended
        resumed = control(testLifecycle='inactive')
        time.sleep(.3)
        status = control()
        frame_delta = status['nativeScheduler']['scheduledFrames'] - resumed['nativeScheduler']['scheduledFrames']
        assert status['nativeScheduler']['active'] and not status['nativeScheduler']['paused'], status
        assert frame_delta >= 5, frame_delta
        report['hidden_to_inactive'] = {'passed': True, 'native_frames': frame_delta}
        control(mode='hidden')
        wait_for(lambda s: not s['engineAlive'])
        control(mode='animated', settleMs=0)
        closing = wait_for(lambda s: s['widgets']['PomoModel'] == 1)
        control(mode='hidden', settleMs=0)
        wait_for(lambda s: not s['engineAlive'] and s['widgets']['PomoModel'] == 0)
        overlap = False
        for attempt in range(10):
            control(mode='animated', settleMs=0)
            wait_for(lambda s: s['widgets']['Texture'] > 0)
            control(holdTeardownMs=500)
            control(mode='hidden', settleMs=0)
            removed = wait_for(lambda s: s['widgets']['PomoModel'] == 0)
            control(mode='animated', settleMs=0)
            wait_for(lambda s: s['widgets']['Texture'] > 0 and s['engineAlive'])
            overlap |= removed['engineAlive']
            control(mode='hidden')
            wait_for(lambda s: not s['engineAlive'])
            if overlap:
                break
        assert overlap, 'Could not observe reopen overlapping engine teardown'
        report['reopen_during_cleanup'] = {'passed': True, 'attempts': attempt + 1}
        report['load_close'] = {'passed': True, 'texture_already_present': closing['widgets']['Texture'] > 0}
        for cycle in range(10):
            started = time.monotonic()
            control(mode='animated', settleMs=0)
            wait_for(lambda s: s['widgets']['Texture'] > 0 and s['engineAlive'])
            opened = time.monotonic() - started
            control(mode='hidden', settleMs=0)
            wait_for(lambda s: not s['engineAlive'] and s['widgets']['PomoModel'] == 0)
            report['rapid_cycles'].append({'cycle': cycle + 1, 'open_s': opened,
                                            'total_s': time.monotonic() - started})
            print('reopen', cycle + 1, round(opened, 3), flush=True)
        for scale in [1, 2.5]:
            control(mode='static', scale=scale)
            wait_for(lambda s: s['widgets']['Texture'] > 0)
            for pose in ['greeting', 'happy', 'surprised', 'sad', 'calm', 'focus', 'rest', 'tired']:
                status = control(pose=pose, capture=True)
                assert status['emotion'] == pose and not status['flutterErrors'], status
                capture = status['capture']
                pixels = base64.b64decode(capture['rgba'])
                image = Image.frombytes('RGBA', (capture['width'], capture['height']), pixels)
                alpha = image.getchannel('A')
                assert alpha.getextrema()[0] == 0 and alpha.getextrema()[1] > 0, pose
                name = f'{pose}-{scale:g}.png'
                image.save(args.output / name)
                item = {'file': name, 'size': image.size, 'visible_bounds': alpha.getbbox()}
                if args.reference:
                    before = np.asarray(Image.open(args.reference / name).convert('RGBA'), dtype=np.float32) / 255
                    after = np.asarray(image, dtype=np.float32) / 255
                    assert before.shape == after.shape
                    # Compare premultiplied visible RGB; transparent RGB is immaterial.
                    delta = before[:, :, :3] * before[:, :, 3:] - after[:, :, :3] * after[:, :, 3:]
                    item['visible_rgb_rmse'] = float(np.sqrt(np.mean(delta ** 2)))
                    item['alpha_mae'] = float(np.mean(np.abs(before[:, :, 3] - after[:, :, 3])))
                report['captures'].append(item)
                print('capture', name, flush=True)
        control(mode='animated')
        animated_frames = []
        frame_start = control()['nativeScheduler']['scheduledFrames']
        for pose in ['calm', 'focus', 'rest', 'focus', 'happy', 'calm']:
            status = control(pose=pose, poseDelayMs=100, capture=True)
            assert not status['flutterErrors'], status
            animated_frames.append(base64.b64decode(status['capture']['rgba']))
        time.sleep(1)
        status = control()
        assert not status['flutterErrors'] and status['widgets']['Texture'] > 0, status
        frame_delta = status['nativeScheduler']['scheduledFrames'] - frame_start
        assert frame_delta >= 15, frame_delta
        assert len(set(animated_frames)) >= 4, 'Transition captures did not change'
        report['transition_motion'] = {'scheduled_frames': frame_delta,
            'distinct_captures': len(set(animated_frames))}
        if args.model_file:
            control(mode='hidden')
            wait_for(lambda s: not s['engineAlive'])
            original = args.model_file.read_bytes()
            try:
                args.model_file.write_bytes(b'broken gzip fixture')
                control(mode='animated', settleMs=0)
                deadline = time.monotonic() + 30
                while True:
                    status = control()
                    if status['flutterErrors'] and not status['engineAlive']:
                        break
                    assert time.monotonic() < deadline, status
                    time.sleep(.05)
                assert len(status['flutterErrors']) == 1, status
                assert 'FormatException' in status['flutterErrors'][0], status
                expected_errors = 1
                report['bad_asset'] = {'released': True, 'error': status['flutterErrors'][0]}
            finally:
                args.model_file.write_bytes(original)
            control(mode='hidden')
            wait_for(lambda s: not s['engineAlive'])
            control(mode='animated')
            wait_for(lambda s: s['widgets']['Texture'] > 0 and s['engineAlive'])
            report['bad_asset']['recovered'] = True

    finally:
        control(mode='hidden')
        status = wait_for(lambda s: not s['engineAlive'])
        report['final_status'] = status
        (args.output / 'checks.json').write_text(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
