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
CHEW_BAND = (1.0, 2.0)    # chewing fundamental, per the literature
WIDE_BAND = (0.5, 4.0)    # broader band for context
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
    chew = band_energy(freqs, power, *CHEW_BAND)
    wide = band_energy(freqs, power, *WIDE_BAND)

    # Dominant frequency in the wide band (where's the action?)
    wmask = (freqs >= WIDE_BAND[0]) & (freqs <= WIDE_BAND[1])
    peak_f = freqs[wmask][np.argmax(power[wmask])] if wmask.any() else 0.0

    return {
        "name": os.path.basename(path),
        "dur": t[-1],
        "chew_index": chew / total if total else 0.0,   # fraction in 1-2 Hz
        "wide_index": wide / total if total else 0.0,
        "peak_hz": peak_f,
        "t": t, "acc": acc, "freqs": freqs, "power": power,
    }


def main(paths):
    results = [analyze(p) for p in paths]

    # --- printed table ---
    print(f"\n{'file':<40} {'dur(s)':>7} {'chew 1-2Hz':>11} {'wide .5-4':>10} {'peak Hz':>8}")
    print("-" * 80)
    for r in results:
        print(f"{r['name']:<40} {r['dur']:>7.1f} "
              f"{r['chew_index']*100:>10.1f}% {r['wide_index']*100:>9.1f}% "
              f"{r['peak_hz']:>8.2f}")
    print()

    # crude verdict if exactly the two canonical files are present
    chew_files = [r for r in results if "chew" in r["name"].lower()]
    talk_files = [r for r in results if "talk" in r["name"].lower()]
    if chew_files and talk_files:
        c = np.mean([r["chew_index"] for r in chew_files])
        k = np.mean([r["chew_index"] for r in talk_files])
        ratio = c / k if k else float("inf")
        print(f"chewing chew-index = {c*100:.1f}%   talking chew-index = {k*100:.1f}%   "
              f"ratio = {ratio:.1f}x")
        if ratio >= 2.0:
            print("=> CLEAN SEPARATION. Chewing's 1-2 Hz band is distinctly hotter. "
                  "Phase 2 cheap-classifier recipe should work.\n")
        elif ratio >= 1.3:
            print("=> PARTIAL separation. Signal is there but not dramatic — "
                  "calibration + more features will matter.\n")
        else:
            print("=> WEAK separation in this clip. Don't panic — check the plot, "
                  "try a crunchier food, longer clip, or other features (rot_mag).\n")

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
        ax_f.axvspan(*CHEW_BAND, color="orange", alpha=0.25, label="chew band 1-2 Hz")
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
