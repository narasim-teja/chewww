//
//  RecorderViewModel.swift
//  chewww
//
//  Glue between MotionManager, CSVLogger, and the SwiftUI view. Owns all
//  observable state the UI renders. Everything here runs on the main actor.
//
//  PHASE 1: pick-label-THEN-record. The user selects ONE `SessionLabel`
//  (and, for eating, an optional `FoodTexture`) before tapping Start;
//  recording is blocked until a label is chosen. The resolved token drives
//  BOTH the filename and the per-row CSV label column (the logger owns the
//  column — see CSVLogger).
//

import Foundation
import Observation
import CoreMotion

@MainActor
@Observable
final class RecorderViewModel {
    // Live status
    var connected = false           // AirPods present (ear-detection)
    var recording = false
    var sampleRateHz: Double = 0
    var sampleCount = 0
    var lastSample: MotionSample?

    // Session bookkeeping
    var lastFileURL: URL?
    var statusMessage = "Ready"

    // MARK: - Labeling (Phase 1)

    /// The activity the user is about to record. `nil` until they pick one —
    /// recording is blocked while nil so every file is labeled.
    var selectedLabel: SessionLabel?

    /// Optional texture tag; only meaningful when `selectedLabel == .eating`.
    var selectedTexture: FoodTexture = .none

    /// Token used for BOTH the filename and the per-row label column,
    /// e.g. "eating-crunchy", "walking". Empty when no label is picked.
    var resolvedToken: String {
        selectedLabel?.token(texture: selectedTexture) ?? ""
    }

    /// Label of the most recently completed session (for the status line and
    /// any UI that wants it without re-parsing the filename).
    var lastRecordedToken = ""

    private let motion = MotionManager()
    private let logger = CSVLogger()

    init() {
        motion.delegate = self
        connected = motion.isDeviceMotionAvailable
        refreshAvailability()
    }

    var motionAvailable: Bool { motion.isDeviceMotionAvailable }

    /// Record-button gate: a label must be chosen AND motion must be available.
    /// (The `connected` observed var flips on the same ear-detection event that
    /// changes availability, so the button re-evaluates reactively in practice.)
    var canRecord: Bool { selectedLabel != nil && motion.isDeviceMotionAvailable }

    var authorizationText: String {
        switch MotionManager.authorizationStatus {
        case .authorized:    return "authorized"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .notDetermined: return "not determined"
        @unknown default:    return "unknown"
        }
    }

    func refreshAvailability() {
        if !motion.isDeviceMotionAvailable {
            statusMessage = "Headphone motion unavailable — connect AirPods"
        } else if !recording {
            statusMessage = "Ready"
        }
    }

    /// Pick a label. Clears a stale texture when switching to a label that
    /// doesn't support one, so e.g. a leftover "crunchy" never leaks into a
    /// walking session.
    func select(_ label: SessionLabel) {
        selectedLabel = label
        if !label.supportsTexture { selectedTexture = .none }
    }

    func toggleRecording() {
        recording ? stop() : start()
    }

    private func start() {
        // Defense in depth behind the disabled button.
        guard selectedLabel != nil else {
            statusMessage = "Pick a label first"
            return
        }
        guard motion.isDeviceMotionAvailable else {
            statusMessage = "No headphone motion — are AirPods connected to this iPhone?"
            return
        }
        sampleCount = 0
        sampleRateHz = 0
        // Snapshot the token ONCE; the logger reuses it for every row.
        let token = resolvedToken
        lastFileURL = logger.start(label: token)
        motion.start()
        recording = true
        statusMessage = "Recording \(token)…"
    }

    private func stop() {
        lastRecordedToken = resolvedToken
        motion.stop()
        let url = logger.stop()
        lastFileURL = url
        recording = false
        statusMessage = url.map { "Saved \($0.lastPathComponent) (\(sampleCount) samples)" }
            ?? "Stopped"
    }
}

// MARK: - MotionManagerDelegate

extension RecorderViewModel: MotionManagerDelegate {
    func motionManager(_ m: MotionManager, didReceive sample: MotionSample) {
        guard recording else { return }
        logger.append(sample)
        lastSample = sample
        sampleCount += 1
    }

    func motionManager(_ m: MotionManager, didChangeConnected connected: Bool) {
        self.connected = connected
        if !connected && recording {
            statusMessage = "Buds removed — still recording"
        }
        refreshAvailability()
    }

    func motionManager(_ m: MotionManager, didChangeRate hz: Double) {
        sampleRateHz = hz
    }
}
