//
//  MotionSample.swift
//  chewww
//
//  One row of AirPods motion data. This is the unit we log to CSV and,
//  in later phases, the unit we window + classify.
//

import CoreMotion
import Foundation

/// A single fused `CMDeviceMotion` sample, flattened for logging.
///
/// AirPods give us *processed* motion only (no raw accel/gyro): attitude,
/// rotation rate, user acceleration, and gravity. We capture all of it plus
/// which bud it came from.
struct MotionSample {
    /// Seconds since the recording started (not since boot). Monotonic.
    let t: Double
    /// Raw sensor timestamp (seconds since device boot) — kept for delta math.
    let sensorTimestamp: TimeInterval

    // Attitude (orientation)
    let roll: Double
    let pitch: Double
    let yaw: Double
    let quatW: Double
    let quatX: Double
    let quatY: Double
    let quatZ: Double

    // Rotation rate (rad/s), gravity-independent
    let rotX: Double
    let rotY: Double
    let rotZ: Double

    // User acceleration (g), gravity removed — this is the chewing signal candidate
    let accX: Double
    let accY: Double
    let accZ: Double

    // Gravity vector (g)
    let gravX: Double
    let gravY: Double
    let gravZ: Double

    /// "left" / "right" / "default" / "unknown" — which bud sourced this sample.
    let sensorLocation: String

    /// CSV header. Keep in lockstep with `csvRow`.
    static let csvHeader =
        "t,sensorTimestamp,roll,pitch,yaw,quatW,quatX,quatY,quatZ,rotX,rotY,rotZ,accX,accY,accZ,gravX,gravY,gravZ,sensorLocation"

    /// One CSV line (no trailing newline).
    var csvRow: String {
        // Fixed-precision keeps file size sane and columns aligned.
        func f(_ v: Double) -> String { String(format: "%.6f", v) }
        return [
            f(t), f(sensorTimestamp),
            f(roll), f(pitch), f(yaw),
            f(quatW), f(quatX), f(quatY), f(quatZ),
            f(rotX), f(rotY), f(rotZ),
            f(accX), f(accY), f(accZ),
            f(gravX), f(gravY), f(gravZ),
            sensorLocation,
        ].joined(separator: ",")
    }

    /// Build from a `CMDeviceMotion`, stamping with elapsed time since start.
    init(motion m: CMDeviceMotion, startedAt start: TimeInterval) {
        self.t = m.timestamp - start
        self.sensorTimestamp = m.timestamp

        let a = m.attitude
        self.roll = a.roll
        self.pitch = a.pitch
        self.yaw = a.yaw
        let q = a.quaternion
        self.quatW = q.w
        self.quatX = q.x
        self.quatY = q.y
        self.quatZ = q.z

        let r = m.rotationRate
        self.rotX = r.x
        self.rotY = r.y
        self.rotZ = r.z

        let ua = m.userAcceleration
        self.accX = ua.x
        self.accY = ua.y
        self.accZ = ua.z

        let g = m.gravity
        self.gravX = g.x
        self.gravY = g.y
        self.gravZ = g.z

        switch m.sensorLocation {
        case .headphoneLeft:  self.sensorLocation = "left"
        case .headphoneRight: self.sensorLocation = "right"
        case .default:        self.sensorLocation = "default"
        @unknown default:     self.sensorLocation = "unknown"
        }
    }
}
