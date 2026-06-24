#!/usr/bin/env python3
"""
separability.py — Phase 0/2 gut-check: does chewing separate from talking?

Reads chewww motion CSVs (50 Hz, columns from MotionSample.swift) and, for each
file, computes the frequency content of the head-motion signal. Chewing should
show a distinct peak in the ~1-2 Hz band; talking / nothing should not.

Usage:
    python3 analysis/separability.py data/chewing.csv data/talking.csv [more.csv ...]

Outputs:
    - A table of band-energy metrics per file (printed).
    - analysis/out/separability.png — time series + FFT spectra, one row per file.

The "chewing index" is the fraction of signal energy that falls in the 1-2 Hz
band. If chewing files score meaningfully higher than talking/nothing files,
the signal is there and the cheap RandomForest/SVM recipe in Phase 2 will work.
"""

import sys
import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")  # no display needed; we save a PNG
import matplotlib.pyplot as plt

FS = 50.0                 # confirmed sample rate (Hz) — Phase 0 finding
# NOTE: literature (on 25 Hz hardware) puts chewing at 1-2 Hz. But on the 50 Hz
# Pro 3, Teja's chewing peaks at ~3.6 Hz with strong 2-4 Hz structure, while
# talking is dominated by <1 Hz head-bob. So the discriminating band is 2-4 Hz,
# not 1-2 Hz. This is a real Phase 0 finding — see docs/chewww.md §2.
CHEW_BAND = (2.0, 4.0)    # empirical chewing band for Pro 3 @ 50 Hz (Teja)
TALK_BAND = (0.3, 1.0)    # talking / head-bob band, for contrast
WIDE_BAND = (0.5, 6.0)    # broader band for context
# Magnitude of (userAcceleration) is our primary chewing-signal candidate:
# gravity-removed, so it isolates active head/jaw motion.


def load(path):
    df = pd.read_csv(path)
    # Resample onto a uniform 50 Hz grid using the 't' column, so FFT is honest
    # even if a few frames dropped. (We saw one ~0.8s startup gap in real data.)
    t = df["t"].to_numpy()
    n = int(round((t[-1] - t[0]) * FS)) + 1
    grid = t[0] + np.arange(n) / FS

    def interp(col):
        return np.interp(grid, t, df[col].to_numpy())

    acc_mag = np.sqrt(interp("accX") ** 2 + interp("accY") ** 2 + interp("accZ") ** 2)
    rot_mag = np.sqrt(interp("rotX") ** 2 + interp("rotY") ** 2 + interp("rotZ") ** 2)
    return grid - grid[0], acc_mag, rot_mag


def spectrum(sig):
    """One-sided amplitude spectrum of a detrended, windowed signal."""
    sig = sig - np.mean(sig)
    win = np.hanning(len(sig))
    sig = sig * win
    fft = np.fft.rfft(sig)
    freqs = np.fft.rfftfreq(len(sig), d=1.0 / FS)
    power = np.abs(fft) ** 2
    return freqs, power


def band_energy(freqs, power, lo, hi):
    mask = (freqs >= lo) & (freqs <= hi)
    return power[mask].sum()


def analyze(path):
    t, acc, rot = load(path)
    freqs, power = spectrum(acc)

    total = band_energy(freqs, power, 0.0, FS / 2)      # all energy
    chew = band_energy(freqs, power, *CHEW_BAND)        # 2-4 Hz
    talk = band_energy(freqs, power, *TALK_BAND)        # 0.3-1 Hz

    # Dominant frequency in the wide band (where's the action?)
    wmask = (freqs >= WIDE_BAND[0]) & (freqs <= WIDE_BAND[1])
    peak_f = freqs[wmask][np.argmax(power[wmask])] if wmask.any() else 0.0

    return {
        "name": os.path.basename(path),
        "dur": t[-1],
        "chew_index": chew / total if total else 0.0,   # fraction in 2-4 Hz
        "talk_index": talk / total if total else 0.0,   # fraction in 0.3-1 Hz
        # The money feature: ratio of chewing-band to talking-band energy.
        # High => chewing. Low => talking. Single most discriminating number.
        "chew_talk_ratio": chew / talk if talk else float("inf"),
        "peak_hz": peak_f,
        "t": t, "acc": acc, "freqs": freqs, "power": power,
    }


def main(paths):
    results = [analyze(p) for p in paths]

    # --- printed table ---
    print(f"\n{'file':<40} {'dur(s)':>7} {'2-4Hz':>7} {'.3-1Hz':>7} "
          f"{'chew/talk':>10} {'peak Hz':>8}")
    print("-" * 84)
    for r in results:
        print(f"{r['name']:<40} {r['dur']:>7.1f} "
              f"{r['chew_index']*100:>6.1f}% {r['talk_index']*100:>6.1f}% "
              f"{r['chew_talk_ratio']:>9.2f}x {r['peak_hz']:>8.2f}")
    print()

    # verdict using the chew/talk band-energy ratio (the discriminating feature)
    chew_files = [r for r in results if "chew" in r["name"].lower()]
    talk_files = [r for r in results if "talk" in r["name"].lower()]
    if chew_files and talk_files:
        c = np.mean([r["chew_talk_ratio"] for r in chew_files])
        k = np.mean([r["chew_talk_ratio"] for r in talk_files])
        sep = c / k if k else float("inf")
        print(f"chewing chew/talk = {c:.2f}x    talking chew/talk = {k:.2f}x    "
              f"separation = {sep:.1f}x")
        if sep >= 3.0:
            print("=> STRONG SEPARATION. The 2-4 Hz chewing band vs <1 Hz talking band "
                  "splits these cleanly. Phase 2 cheap-classifier recipe will work.\n")
        elif sep >= 1.5:
            print("=> DECENT separation. Signal is clearly there; calibration + a few "
                  "more features tighten it up.\n")
        else:
            print("=> WEAK separation in this clip. Check the plot; try a crunchier "
                  "food, longer clip, or other features (rot_mag).\n")

    # --- plot ---
    os.makedirs("analysis/out", exist_ok=True)
    n = len(results)
    fig, axes = plt.subplots(n, 2, figsize=(13, 3.2 * n), squeeze=False)
    for i, r in enumerate(results):
        ax_t, ax_f = axes[i]
        ax_t.plot(r["t"], r["acc"], lw=0.6)
        ax_t.set_title(f"{r['name']} — |userAccel| over time")
        ax_t.set_xlabel("s"); ax_t.set_ylabel("g")

        ax_f.plot(r["freqs"], r["power"], lw=0.8)
        ax_f.axvspan(*TALK_BAND, color="steelblue", alpha=0.18, label="talk band .3-1 Hz")
        ax_f.axvspan(*CHEW_BAND, color="orange", alpha=0.25, label="chew band 2-4 Hz")
        ax_f.set_xlim(0, 6)
        ax_f.set_title(f"spectrum (peak {r['peak_hz']:.2f} Hz, "
                       f"chew-index {r['chew_index']*100:.1f}%)")
        ax_f.set_xlabel("Hz"); ax_f.set_ylabel("power"); ax_f.legend(fontsize=8)

    fig.tight_layout()
    out = "analysis/out/separability.png"
    fig.savefig(out, dpi=130)
    print(f"plot saved -> {out}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])
