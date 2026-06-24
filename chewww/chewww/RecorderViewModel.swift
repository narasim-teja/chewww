//
//  RecorderViewModel.swift
//  chewww
//
//  Glue between MotionManager, CSVLogger, and the SwiftUI view. Owns all
//  observable state the UI renders. Everything here runs on the main actor.
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

    /// What to call this session (used in the filename). Phase 1 will swap this
    /// for the eating/talking/etc. labels; for Phase 0 it's freeform.
    var sessionLabel = "freeform"

    private let motion = MotionManager()
    private let logger = CSVLogger()

    init() {
        motion.delegate = self
        connected = motion.isDeviceMotionAvailable
        refreshAvailability()
    }

    var motionAvailable: Bool { motion.isDeviceMotionAvailable }

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

    func toggleRecording() {
        recording ? stop() : start()
    }

    private func start() {
        guard motion.isDeviceMotionAvailable else {
            statusMessage = "No headphone motion — are AirPods connected to this iPhone?"
            return
        }
        sampleCount = 0
        sampleRateHz = 0
        lastFileURL = logger.start(label: sessionLabel)
        motion.start()
        recording = true
        statusMessage = "Recording \(sessionLabel)…"
    }

    private func stop() {
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
