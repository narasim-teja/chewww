# chewww

Eating detection via AirPods Pro 3 IMU. See [docs/chewww.md](docs/chewww.md) for the full concept and phased plan.

## Status — Phase 0 (spike)

A native SwiftUI iOS app that streams fused `CMDeviceMotion` from AirPods via
`CMHeadphoneMotionManager`, logs it to CSV (shareable from the Files app), and
shows the **real sample rate** live so we can confirm the ~25 Hz assumption.

### Layout

```
chewww/                     repo root
├── docs/chewww.md          the idea + research + roadmap
└── chewww/                 Xcode project
    ├── chewww.xcodeproj
    └── chewww/
        ├── chewwwApp.swift          app entry
        ├── ContentView.swift        Phase 0 UI (start/stop, live Hz, status, share)
        ├── RecorderViewModel.swift  @Observable glue: motion → logger → UI
        ├── MotionManager.swift      CMHeadphoneMotionManager wrapper + rate estimate
        ├── CSVLogger.swift          buffered CSV writer to Documents/
        ├── MotionSample.swift       one row of motion data + CSV schema
        └── Info.plist               UIFileSharingEnabled (other keys via build settings)
```

### Build & run

Requires a **physical iPhone** with AirPods connected to *that phone* — the
simulator returns no headphone motion.

1. Open `chewww/chewww.xcodeproj` in Xcode 26+.
2. Select your iPhone as the run destination.
3. Run (⌘R). Accept the Motion & Fitness permission prompt on first launch.
4. Tap **Start Recording**, do an activity, tap **Stop**, then **Share last CSV**.

CSVs also appear in **Files ▸ On My iPhone ▸ chewww**.

### CSV schema

`t, sensorTimestamp, roll, pitch, yaw, quatW, quatX, quatY, quatZ, rotX, rotY, rotZ, accX, accY, accZ, gravX, gravY, gravZ, sensorLocation`

- `t` — seconds since recording started
- attitude (`roll/pitch/yaw` + quaternion), `rot*` rotation rate (rad/s),
  `acc*` user acceleration (g, gravity-removed — the chewing-signal candidate),
  `grav*` gravity vector, `sensorLocation` = left/right bud.

### Phase 0 exit criteria

- [ ] Confirm real sample rate (~25 Hz?) via the live Hz readout.
- [ ] Confirm connect/disconnect (ear-detection) events fire.
- [ ] Export a CSV and eyeball your own head motion.
