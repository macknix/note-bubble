#!/usr/bin/env python3
"""Synthesise five bubble-pop sounds into Resources/Sounds/.

These are stand-ins: Pixabay blocks automated downloads (HTTP 403) and its API
serves only images and video, so the "Bubble Pop 0N" files cannot be fetched as
part of a build. Drop real recordings in over the top using the same filenames
and the app will pick them up untouched — nothing else needs to change.

The model is a collapsing air cavity: a rising sine (Minnaert resonance climbs as
the bubble shrinks), an exponential amplitude decay, and a short noise transient
for the initial rupture.
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44_100

# (base Hz, end Hz, seconds, decay, noise level) — low/slow reads as a big bubble,
# high/fast as a small one, so the five are audibly different.
VOICES = [
    (420, 980, 0.150, 26, 0.22),
    (530, 1_180, 0.130, 30, 0.18),
    (660, 1_450, 0.115, 34, 0.26),
    (790, 1_720, 0.100, 38, 0.20),
    (940, 2_050, 0.090, 43, 0.28),
]


def render(f0, f1, duration, decay, noise_level, seed):
    rng = random.Random(seed)
    total = int(SAMPLE_RATE * duration)
    samples = []
    phase = 0.0
    smoothed_noise = 0.0

    for i in range(total):
        t = i / SAMPLE_RATE
        x = t / duration

        # Pitch sweeps up fastest at the moment of rupture, then eases.
        freq = f0 + (f1 - f0) * (x ** 0.55)
        phase += 2 * math.pi * freq / SAMPLE_RATE

        envelope = math.exp(-decay * t)
        body = math.sin(phase) * envelope
        # A touch of second harmonic stops it sounding like a pure test tone.
        body += 0.22 * math.sin(2 * phase) * envelope * envelope

        # Rupture click: white noise low-passed by a one-pole filter and dumped
        # almost immediately.
        white = rng.uniform(-1.0, 1.0)
        smoothed_noise += 0.45 * (white - smoothed_noise)
        body += smoothed_noise * noise_level * math.exp(-260 * t)

        # Short fade at the tail so the buffer never ends on a discontinuity.
        if x > 0.85:
            body *= (1 - x) / 0.15

        samples.append(body)

    peak = max(abs(s) for s in samples) or 1.0
    return [int(max(-1.0, min(1.0, s / peak * 0.82)) * 32_767) for s in samples]


def write_wav(path, samples):
    with wave.open(path, "w") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(b"".join(struct.pack("<h", s) for s in samples))


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    target = os.path.join(root, "Resources", "Sounds")
    os.makedirs(target, exist_ok=True)

    for index, (f0, f1, duration, decay, noise) in enumerate(VOICES, start=1):
        path = os.path.join(target, f"pop-{index}.wav")
        write_wav(path, render(f0, f1, duration, decay, noise, seed=index * 7919))
        print(f"wrote {os.path.relpath(path, root)}")


if __name__ == "__main__":
    main()
