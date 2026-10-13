"""Generate original focus cue auditions; never replace application assets.

Run with Python 3 and NumPy. Outputs include a self-contained listening page,
16-bit stereo WAV files, and measured audio levels. No external recordings,
audio APIs, credentials, or network access are used.
"""

from __future__ import annotations

import base64
import io
import json
import math
from pathlib import Path
import wave

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts" / "focus-sounds"
RATE = 44100
STYLES = {
    "warm": ("Warm electronic", "Rounded electric-piano tones; the recommended starting point."),
    "kalimba": ("Soft kalimba", "A synthesized wooden pluck with restrained metallic overtones."),
    "glass": ("Airy glass", "Light bell-like tones with a delicate, short shimmer."),
    "velvet": ("Velvet keys", "Low, rounded keys with a gentle chorus and a soft major-sixth landing."),
    "bamboo": ("Bamboo steps", "Dry wooden mallets; light, intimate, and quietly playful."),
    "porcelain": ("Porcelain bells", "Small ceramic-like bells with a pearly, soft resonance."),
    "pulse": ("Neon pulse", "A springy low synth with a syncopated, forward-moving rhythm."),
    "spark": ("Morning spark", "Bright plucked keys and a quick, uplifting arpeggio."),
    "arcade": ("Pocket arcade", "Rounded triangle-wave notes with a compact game-like reward."),
    "water": ("Water drops", "Bubbly droplets with little pitch slides and a playful response."),
    "cosmic": ("Orbit bloom", "An airy, slowly opening chord with a suspended sense of space."),
    "felt": ("Felt piano", "A muted piano-like touch and a quiet, intimate ending."),
}
GROUPS = {
    "More soft sounds": ("Three new variations on the original gentle direction.", ["velvet", "bamboo", "porcelain"]),
    "Active & upbeat": ("Energy from rhythm and timbre, at the same target level as the soft families.", ["pulse", "spark", "arcade"]),
    "Something different": ("Three contrasting textures: water, space, and felt keys.", ["water", "cosmic", "felt"]),
    "First round": ("The original three families, kept here for comparison.", ["warm", "kalimba", "glass"]),
}
# Each entry is (partials: ratio/amplitude/decay, attack seconds).
TIMBRES = {
    "velvet": ([(1, 1, .32), (2, .25, .17), (3, .045, .12)], .024),
    "bamboo": ([(1, 1, .12), (2.72, .24, .038), (4.9, .10, .022)], .006),
    "porcelain": ([(1, 1, .30), (2.36, .16, .13), (4.12, .065, .07)], .014),
    "pulse": ([(1, 1, .16), (2, .34, .09), (3, .19, .06), (4, .06, .035)], .006),
    "spark": ([(1, 1, .19), (2, .38, .095), (3, .13, .06), (5, .04, .035)], .005),
    "arcade": ([(1, 1, .15), (3, -.111, .14), (5, .04, .11), (7, -.0204, .08)], .008),
    "water": ([(1, 1, .13), (2, .085, .055)], .012),
    "cosmic": ([(1, 1, .55), (2, .12, .4), (3, .065, .3)], .07),
    "felt": ([(1, 1, .27), (2.002, .34, .13), (3.006, .14, .07), (4.012, .03, .035)], .009),
}
# Root MIDI note, note tail, and event patterns (time, semitone offset, gain).
ARRANGEMENTS = {
    "velvet": (57, .78, [(0, 0, 1), (.18, 4, .82)], [(0, 0, .8), (.18, 4, .72), (.36, 9, .6), (.36, 7, .3)]),
    "bamboo": (67, .43, [(0, 0, 1), (.12, 7, .7)], [(0, 0, .82), (.12, 4, .72), (.26, 7, .78), (.44, 12, .65)]),
    "porcelain": (65, .78, [(0, 0, 1), (.21, 7, .72)], [(0, 0, .85), (.22, 7, .72), (.43, 14, .48), (.43, 4, .3)]),
    "pulse": (55, .45, [(0, 0, 1), (.115, 0, .55), (.24, 7, .85)], [(0, 0, 1), (.105, 7, .63), (.26, 9, .73), (.38, 12, .85), (.38, 0, .3)]),
    "spark": (64, .52, [(0, 0, .85), (.09, 4, .7), (.18, 7, .85)], [(0, 0, .85), (.09, 4, .72), (.18, 7, .68), (.29, 9, .72), (.42, 12, .82)]),
    "arcade": (60, .38, [(0, 0, .85), (.085, 12, .62)], [(0, 0, .8), (.105, 7, .8), (.21, 12, .7), (.37, 16, .6), (.50, 12, .8)]),
    "water": (69, .47, [(0, 0, 1), (.17, 7, .72)], [(0, 0, .85), (.15, 4, .7), (.34, 9, .65), (.53, 12, .52)]),
    "cosmic": (57, 1.25, [(0, 0, .7), (.08, 7, .45), (.20, 14, .24)], [(0, 0, .75), (.16, 7, .52), (.34, 12, .4), (.52, 16, .33), (.70, 19, .24)]),
    "felt": (60, .74, [(0, 0, .9), (.19, 4, .7)], [(0, 0, .8), (.18, 4, .6), (.39, 7, .64), (.39, 12, .30)]),
}
CUES = {
    "start": ("Start", 0.85, [(0.0, 392.0, 0.62, 1.0), (0.15, 493.883, 0.65, 0.86)]),
    "pause": ("Pause", 0.46, [(0.0, 329.628, 0.43, 0.8)]),
    "resume": ("Resume", 0.64, [(0.0, 493.883, 0.58, 0.86)]),
    "complete": ("Complete", 1.85, [
        (0.0, 392.0, 1.0, 0.83),
        (0.14, 493.883, 1.0, 0.75),
        (0.29, 587.330, 1.1, 0.76),
        (0.48, 783.991, 1.25, 0.62),
        (0.48, 392.0, 1.25, 0.24),
    ]),
}
TARGET_RMS_DB = {"start": -24.0, "pause": -27.0, "resume": -25.0, "complete": -23.0}


def cue_spec(style: str, cue: str) -> tuple:
    if style not in ARRANGEMENTS:
        return CUES[cue]
    root, tail, start, complete = ARRANGEMENTS[style]
    patterns = {
        "start": start,
        "pause": [(0, -5, .8)],
        "resume": [(0, 4, .85), (.10, 7, .55)] if style in {"pulse", "spark", "arcade"} else [(0, 7, .85)],
        "complete": complete,
    }
    if cue == "pause":
        tail *= .62
    elif cue == "resume":
        tail *= .8
    events = [(time, 440 * 2 ** ((root + pitch - 69) / 12), tail, gain) for time, pitch, gain in patterns[cue]]
    duration = round(max(time + length for time, _, length, _ in events) + .12, 3)
    return CUES[cue][0], duration, events


def note(style: str, frequency: float, duration: float) -> np.ndarray:
    t = np.arange(round(duration * RATE)) / RATE
    if style == "warm":
        partials = [(1.0, 1.0, 0.24), (2.0, 0.19, 0.13), (3.0, 0.055, 0.085)]
        attack = 0.016
    elif style == "kalimba":
        partials = [(1.0, 1.0, 0.22), (2.76, 0.11, 0.075), (5.40, 0.026, 0.035)]
        attack = 0.007
    elif style == "glass":
        partials = [(1.0, 1.0, 0.32), (2.01, 0.17, 0.23), (3.98, 0.035, 0.12)]
        attack = 0.023
    else:
        partials, attack = TIMBRES[style]
    result = np.zeros_like(t)
    cycles = frequency * t
    if style == "water":
        # A quick downward glide makes a rounded droplet rather than a fixed bell.
        cycles += frequency * .32 * .022 * (1 - np.exp(-t / .022))
    elif style == "pulse":
        cycles += frequency * .065 * .018 * (1 - np.exp(-t / .018))
    for ratio, level, decay in partials:
        # Reduce high partials further for the highest completion note.
        level /= 1.0 + (frequency * ratio / 2600.0) ** 4
        phase = 2 * math.pi * frequency * ratio * t if style not in TIMBRES else 2 * math.pi * ratio * cycles
        result += level * np.sin(phase) * np.exp(-t / decay)
    if style in {"velvet", "cosmic"}:
        result += .16 * np.sin(2 * math.pi * frequency * 1.003 * t) * np.exp(-t / (.5 if style == "cosmic" else .28))
    if style == "cosmic":
        result *= .86 + .14 * np.cos(2 * math.pi * 2.3 * t)
    result *= 1.0 - np.exp(-t / attack)
    fade = min(len(result), round(0.07 * RATE))
    result[-fade:] *= np.linspace(1.0, 0.0, fade) ** 2
    return result


def synthesize(style: str, cue: str) -> np.ndarray:
    _, duration, events = cue_spec(style, cue)
    dry = np.zeros(round(duration * RATE))
    for offset, frequency, length, gain in events:
        sound = note(style, frequency, length) * gain
        start = round(offset * RATE)
        count = min(len(sound), len(dry) - start)
        dry[start:start + count] += sound[:count]
    # Small, asymmetric early reflections add space while retaining mono clarity.
    stereo = np.column_stack((dry, dry))
    reflections = [(0.037, 0.055, 0.85), (0.061, 0.035, 1.15), (0.097, 0.018, 0.9)]
    if style == "cosmic":
        reflections += [(.17, .06, .85), (.27, .035, 1.15)]
    for seconds, gain, pan in reflections:
        shift = round(seconds * RATE)
        stereo[shift:, 0] += dry[:-shift] * gain * pan
        stereo[shift:, 1] += dry[:-shift] * gain / pan
    fade = round(0.06 * RATE)
    stereo[-fade:] *= (np.linspace(1.0, 0.0, fade) ** 2)[:, None]
    stereo -= stereo.mean(axis=0)
    # A final fade keeps DC correction from introducing nonzero file boundaries.
    ramp = round(0.004 * RATE)
    stereo[:ramp] *= np.linspace(0.0, 1.0, ramp)[:, None]
    stereo[-ramp:] *= np.linspace(1.0, 0.0, ramp)[:, None]
    # Match active-signal RMS, rather than letting silence inflate perceived level.
    energy = np.mean(stereo * stereo, axis=1)
    active = energy > energy.max() * 0.001
    rms = np.sqrt(energy[active].mean())
    stereo *= 10 ** (TARGET_RMS_DB[cue] / 20) / rms
    peak = np.abs(stereo).max()
    if peak > 10 ** (-8.0 / 20):
        stereo *= 10 ** (-8.0 / 20) / peak
    return stereo


def wav_bytes(samples: np.ndarray) -> bytes:
    pcm = np.rint(samples * 32767).astype("<i2")
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    return buffer.getvalue()


def data_url(data: bytes) -> str:
    return "data:audio/wav;base64," + base64.b64encode(data).decode("ascii")


def metrics(samples: np.ndarray) -> dict:
    energy = np.mean(samples * samples, axis=1)
    active = energy > energy.max() * 0.001
    return {
        "duration_seconds": round(len(samples) / RATE, 3),
        "peak_dbfs": round(20 * math.log10(np.abs(samples).max()), 2),
        "active_rms_dbfs": round(10 * math.log10(energy[active].mean()), 2),
        "sample_rate": RATE,
        "channels": 2,
        "bits_per_sample": 16,
    }


def listening_page(sources: dict) -> str:
    cards = {}
    for style, (title, description) in STYLES.items():
        buttons = "".join(
            f'<div class="cue"><button data-play="{style}/{cue}">{label} <span>{duration:.2f}s</span></button>'
            f'<a data-download="{style}/{cue}" download="{style}_focus_{cue}.wav" aria-label="Download {title} {label}">↓ WAV</a></div>'
            for cue in CUES
            for label, duration, _ in [cue_spec(style, cue)]
        )
        cards[style] = (f'<section><h3>{title}</h3><p>{description}</p>{buttons}'
                        f'<button class="sequence" data-sequence="{style}">Play all four</button></section>')
    groups = "".join(
        f'<div class="group"><h2>{title}</h2><p>{description}</p><div class="grid">'
        + "".join(cards[style] for style in styles) + '</div></div>'
        for title, (description, styles) in GROUPS.items()
    )
    old_buttons = "".join(f'<button data-play="current/{cue}">{label}</button>' for cue, (label, _, _) in CUES.items())
    payload = json.dumps(sources, separators=(",", ":"))
    return """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pomodoist · Sound auditions</title><style>
:root{color-scheme:light dark;--bg:#fafafa;--fg:#171717;--muted:#666;--card:#fff;--border:#ddd;--accent:#b83025}
@media(prefers-color-scheme:dark){:root{--bg:#101010;--fg:#eee;--muted:#aaa;--card:#191919;--border:#383838;--accent:#ff857b}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 system-ui,sans-serif}
main{max-width:1120px;margin:40px auto;padding:0 24px}h1{font-size:32px;line-height:1.2}h2{font-size:26px;margin:0}h3{font-size:22px;margin:0}.group{margin:36px 0}
p{color:var(--muted)}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px}
section{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:22px}
section p{min-height:78px}.cue{display:flex;align-items:center;gap:10px;margin:12px 0}
button{cursor:pointer;color:var(--fg);background:var(--card);border:1px solid var(--border);border-radius:8px;padding:11px 13px;font:inherit;min-height:44px}
button:hover{border-color:var(--accent)}button:focus-visible,a:focus-visible,input:focus-visible{outline:3px solid var(--accent);outline-offset:3px}
.cue button{flex:1;text-align:left;display:flex;justify-content:space-between;gap:8px}.cue span{color:var(--muted);font-size:13px;align-self:center}
a{color:var(--accent);font-size:13px;padding:10px 0;white-space:nowrap}.sequence{width:100%;margin-top:12px}
.toolbar{display:flex;align-items:center;gap:16px;flex-wrap:wrap;margin:24px 0}.toolbar label{display:flex;align-items:center;gap:12px}
input{accent-color:var(--accent);width:150px}#status{min-height:26px;color:var(--muted)}details{margin:26px 0}summary{cursor:pointer;min-height:44px}
.original{display:flex;gap:12px;flex-wrap:wrap;margin-top:12px}footer{color:var(--muted);font-size:14px}
@media(max-width:820px){.grid{grid-template-columns:1fr}section p{min-height:0}main{margin-top:24px}}
</style></head><body><main><h1>Pomodoist · Sound auditions</h1>
<p>Nine new sound families, plus the original three. Each has Start, Pause, Resume, and Complete. Compare one cue across styles or play a full sequence.</p>
<div class="toolbar"><label for="volume">Volume <input id="volume" type="range" min="0" max="100" value="55"><output id="level">55%</output></label>
<button id="stop">Stop</button></div><p id="status" role="status" aria-live="polite">Ready. Start at a comfortable listening volume.</p>
""" + groups + """
<details><summary>Compare current application sounds</summary><div class="original">""" + old_buttons + """</div></details>
<footer>Initial volume matches the application's 55% player setting. Candidate files have matched active RMS by cue and at least 8 dB peak headroom.
Current assets retain their original levels. These are audition candidates; they are not installed in the app. Everything on this page works offline.</footer>
</main><script>
const sources = """ + payload + """;
document.querySelectorAll('[data-download]').forEach(link => { link.href = sources[link.dataset.download]; });
const player = new Audio();
const volume = document.getElementById('volume');
const status = document.getElementById('status');
let generation = 0;
let finishPending = null;
player.volume = 0.55;
volume.addEventListener('input', () => {
  player.volume = Number(volume.value) / 100;
  document.getElementById('level').textContent = volume.value + '%';
});
function stop() {
  generation++;
  player.pause();
  player.currentTime = 0;
  if (finishPending) finishPending(false);
  status.textContent = 'Stopped';
}
function play(key, token) {
  if (token !== generation) return Promise.resolve(false);
  status.textContent = key.replace('/', ' · ');
  return new Promise(resolve => {
    const finish = success => {
      if (finishPending !== finish) return;
      player.onended = null;
      player.onerror = null;
      if (finishPending === finish) finishPending = null;
      resolve(success);
    };
    finishPending = finish;
    player.onended = () => finish(true);
    player.onerror = () => { status.textContent = 'Playback failed. Download the WAV and open it in an audio player.'; finish(false); };
    player.src = sources[key];
    player.play().catch(() => {
      if (token === generation) status.textContent = 'Playback could not start. Download the WAV or try another browser.';
      finish(false);
    });
  });
}
document.getElementById('stop').addEventListener('click', stop);
document.querySelectorAll('[data-play]').forEach(button => button.addEventListener('click', async () => {
  stop(); const token = generation;
  if (await play(button.dataset.play, token) && token === generation) status.textContent = 'Ready';
}));
document.querySelectorAll('[data-sequence]').forEach(button => button.addEventListener('click', async () => {
  stop(); const token = generation;
  for (const cue of ['start', 'pause', 'resume', 'complete']) {
    if (token !== generation || !await play(button.dataset.sequence + '/' + cue, token)) return;
    await new Promise(resolve => setTimeout(resolve, 450));
  }
  if (token === generation) status.textContent = 'Ready';
}));
</script></body></html>"""


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    sources = {}
    manifest = {"origin": "Original procedural synthesis; no third-party recordings.", "groups": {title: styles for title, (_, styles) in GROUPS.items()}, "candidates": {}}
    for style in STYLES:
        folder = OUTPUT / style
        folder.mkdir(exist_ok=True)
        sequence = [np.zeros((round(0.25 * RATE), 2))]
        for cue in CUES:
            samples = synthesize(style, cue)
            data = wav_bytes(samples)
            (folder / f"focus_{cue}.wav").write_bytes(data)
            sources[f"{style}/{cue}"] = data_url(data)
            manifest["candidates"][f"{style}/{cue}"] = metrics(samples)
            sequence.extend([samples, np.zeros((round(0.45 * RATE), 2))])
        (folder / "demo.wav").write_bytes(wav_bytes(np.concatenate(sequence)))
    for cue in CUES:
        original = ROOT / "apps" / "flutter" / "assets" / "sounds" / f"focus_{cue}.wav"
        if not original.exists():
            original = original.parent / "soft_kalimba" / original.name
        sources[f"current/{cue}"] = data_url(original.read_bytes())
    (OUTPUT / "index.html").write_text(listening_page(sources), encoding="utf-8")
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(STYLES)} families, {len(manifest['candidates'])} cues, and {len(STYLES)} demos in {OUTPUT}")


if __name__ == "__main__":
    main()
