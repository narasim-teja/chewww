//
//  MotionManager.swift
//  chewww
//
//  Wraps CMHeadphoneMotionManager: authorizes motion, streams CMDeviceMotion
//  from the AirPods, reports ear-detection (buds in/out), and measures the
//  REAL sample rate from timestamp deltas — Phase 0 open question #1.
//
//  IMPORTANT: requires NSMotionUsageDescription in Info.plist or the stream
//  silently fails. Only delivers data on a physical device with AirPods
//  connected to THIS phone — the simulator returns nothing.
//

import CoreMotion
import Foundation

/// What the UI/recorder needs to react to. Delivered on the main thread.
@MainActor
protocol MotionManagerDelegate: AnyObject {
    func motionManager(_ m: MotionManager, didReceive sample: MotionSample)
    func motionManager(_ m: MotionManager, didChangeConnected connected: Bool)
    func motionManager(_ m: MotionManager, didChangeRate hz: Double)
}

@MainActor
final class MotionManager: NSObject {
    weak var delegate: MotionManagerDelegate?

    private let manager = CMHeadphoneMotionManager()

    /// Dedicated serial queue for the CoreMotion push handler. Per Apple, do
    /// NOT pass .main here — handler work shouldn't block the UI. We hop back
    /// to @MainActor before touching any shared/UI state.
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.narasim.chewww.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var startTimestamp: TimeInterval?

    // --- live sample-rate estimation (sliding window over recent deltas) ---
    private var recentTimestamps: [TimeInterval] = []
    private let rateWindow = 50          // ~2 s at 25 Hz
    private var lastRateReport: TimeInterval = 0

    private(set) var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Whether the device even has headphone motion available right now.
    var isDeviceMotionAvailable: Bool { manager.isDeviceMotionAvailable }

    /// Current motion authorization. `.notDetermined` until the first
    /// `startDeviceMotionUpdates` call triggers the system prompt.
    static var authorizationStatus: CMAuthorizationStatus {
        CMHeadphoneMotionManager.authorizationStatus()
    }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        guard !isRunning else { return }

        startTimestamp = nil
        recentTimestamps.removeAll(keepingCapacity: true)
        lastRateReport = 0
        isRunning = true

        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            // We're on `queue` here (background). Marshal to MainActor.
            Task { @MainActor in
                self.handle(motion)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    // MARK: - Main-actor sample handling

    private func handle(_ motion: CMDeviceMotion) {
        if startTimestamp == nil { startTimestamp = motion.timestamp }
        let start = startTimestamp ?? motion.timestamp

        let sample = MotionSample(motion: motion, startedAt: start)
        delegate?.motionManager(self, didReceive: sample)

        updateRate(with: motion.timestamp)
    }

    private func updateRate(with ts: TimeInterval) {
        recentTimestamps.append(ts)
        if recentTimestamps.count > rateWindow {
            recentTimestamps.removeFirst(recentTimestamps.count - rateWindow)
        }
        guard recentTimestamps.count >= 2,
              let first = recentTimestamps.first,
              let last = recentTimestamps.last,
              last > first else { return }

        let hz = Double(recentTimestamps.count - 1) / (last - first)

        // Throttle UI rate updates to ~4/s.
        if ts - lastRateReport > 0.25 {
            lastRateReport = ts
            delegate?.motionManager(self, didChangeRate: hz)
        }
    }
}

// MARK: - Ear-detection (connect/disconnect) events

extension MotionManager: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.delegate?.motionManager(self, didChangeConnected: true)
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.delegate?.motionManager(self, didChangeConnected: false)
        }
    }
}
