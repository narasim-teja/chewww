# chewww — Eating Detection via AirPods Pro 3 IMU

> Working title. An all-in-one passive food-intake tracker built on AirPods motion sensing. Detect *that* a user is eating (chewing), prompt them to log *what*, and become the WHOOP-equivalent for diet without any new hardware.

**Status:** Phase 0 complete (spike proven) → starting Phase 1
**Owner:** Teja
**Target:** TestFlight launch (v1)
**Last updated:** June 2026

---

## 1. The Idea

The AirPods motion API exposes the same head-tracking data that powers Spatial Audio. A viral posture app (Posture Pal lineage) proved the data is "just sitting there unused" — no new permission, no extra battery. The insight: **the in-ear IMU is essentially a chewing sensor.** Jaw motion during chewing produces a rhythmic ~1–2 Hz signal at the ear that is distinct from talking, head nods, or just sitting.

chewww turns AirPods into a passive eating detector:

1. Passively monitor IMU while buds are worn.
2. Detect an **eating episode** (chewing bout aggregation).
3. Fire a notification → user logs food metrics (calories / macros / freeform).
4. Detection only needs to be good enough to *prompt*. The human closes the accuracy gap. This sidesteps the genuinely hard problem of quantifying intake from motion alone.

### Why this can work (research-backed)

| Finding | Source |
|---|---|
| In-ear IMU detects chewing at **95% accuracy**, beats audio; fusion → **97%** | Lotfi et al. 2020 (eSense) |
| IMChew: **91% accuracy/F1** chewing detection, **9.5% MAPE** chew count (LOSO, n=8) | Ketmalasiri et al. |
| EarBit: behind-ear IMU = chewing sensor, **93% accuracy** @ 1s resolution, recognized all-but-one eating episode in the wild | Bae et al. (EarBit) |
| Standard pipeline: 4s window = chewing, 20s = bout, bouts within 2 min = episode | Chun et al. / survey |

### Known hard edges (designing around them)

- **Generalization is the real enemy, not talking.** IMU-from-earbuds has *limited generalizability* for short/sporadic chewing on unseen users. The 95%+ numbers are sustained meals. **Mitigation: personalized model + per-user calibration from day one.**
- **Drinking is hard and deferred to v2.** Water swallowing is near-silent with minimal jaw motion. Reliable fluid detection in the literature needs throat mics / sEMG at the larynx — which we don't have. We *capture* drinking data in v1 to mine for findings, but don't ship detection.
- **Short snacks are the failure zone.** A few bites are far harder than a full meal. Expect this and label aggressively.

---

## 2. Hardware & API Reality (the constraint that shapes everything)

`CMHeadphoneMotionManager` (CoreMotion) gives fused `CMDeviceMotion`: **attitude, user acceleration, rotation rate**.

- **Sample rate: 50 Hz confirmed on AirPods Pro 3** (Phase 0 finding, June 2026 — measured rock-solid 20 ms deltas across real recordings). This is **2× the ~25 Hz the literature assumed** from older buds. The doc was originally scoped for ~25 Hz; the Pro 3 streams richer. Plenty for chewing (~1–2 Hz, sits at ~1/25 of Nyquist — pristine), with real headroom for cleaner FFT features, better short-snack detection, and faster micro-events the 25 Hz assumption ruled out. (API max is 100 Hz; headphone motion historically streamed lower, but the Pro 3 gives 50.)
- **No raw accel/gyro** from AirPods — only the processed `CMDeviceMotion`. The 800 Hz / 200 Hz `CMBatchedSensorManager` path is **Apple-Watch-only + requires an active HealthKit workout** — does NOT apply to AirPods.
- **Ear-detection is free signal.** Buds out → disconnect event; back in → connect event. Use it for "are they even wearing it."
- **Required:** `NSMotionUsageDescription` in Info.plist or the stream silently fails.
- Works on AirPods Pro (incl. Pro 3), AirPods 3, AirPods Max, Beats Fit Pro.

### Stack decision (one firm call)

- **Sensor app = native iOS / Swift.** Non-negotiable. `CMHeadphoneMotionManager` has no real React Native bridge, and the background-execution + sample-timing details matter too much to fight a wrapper. (Resist the RN instinct here.)
- **Backend = TypeScript / Bun.** Food-logging API, sync, later cloud model training. This is where the TS/Bun world belongs.

---

## 3. Phased Plan

> Keep an open mind on the data. The phases below are the skeleton; **expect to improvise based on what the labeled dataset actually shows.** If chewing FFT separation is cleaner than expected, simplify. If short snacks are a mess, lean harder into calibration.

### Phase 0 — Spike (a few hours)

**Goal:** Prove you can stream + export labeled `CMDeviceMotion` from your Pro 3.

- [x] ~~Fork `tukuyo/AirPodsPro-Motion-Sampler`~~ → built a fresh native SwiftUI app instead (we own it end-to-end; becomes the Phase 1/3 app directly).
- [x] Add `NSMotionUsageDescription` to Info.plist (+ `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace` for Files-app CSV access).
- [x] Stream attitude / user acceleration / rotation rate (+ quaternion, gravity, sensor location) → CSV.
- [x] **Verified real sample rate** by timestamping deltas → **50 Hz, rock-solid** (not 25 — see §2).
- [x] Connect/disconnect (ear-detection) events wired via `CMHeadphoneMotionManagerDelegate`.

**Exit:** ✅ A CSV of your own head motion you can open and eyeball. Done — two ~50s recordings captured & analyzed (`data/`, gitignored).

### Phase 1 — Be your own dataset (weekend core)

**Goal:** Build the labeled dataset. This is where the project lives or dies.

- [ ] In-app logging mode: tap `eating` / `drinking` / `talking` / `nothing` → log windowed motion + label.
- [ ] Collect **15–20 sessions** across contexts:
  - Crunchy vs soft food (matters a lot)
  - Talking while sitting + talking while walking
  - Just sitting / passive
  - Drinking (capture for v2 mining — label it, don't detect on it yet)
- [ ] Store raw windows + labels. You are the only labeler v1 needs (personalized model).

**Exit:** A clean labeled dataset + first eyeball findings on separability.

**Open question to revisit here:** does talking-while-walking contaminate the eating signal? Note findings, improvise.

### Phase 2 — Classifier

**Goal:** Hit published numbers with the cheap proven recipe. Don't reach for deep learning first.

> **De-risked early (June 2026 separability check).** On a 30s pure-chew vs 30s pure-talk clip, the activities separate by **7×** on a single FFT-band feature — the cheap recipe is clearly viable, no deep learning needed. **Key correction: chewing peaks at ~3.6 Hz with strong 2–4 Hz structure on the Pro 3 @ 50 Hz, NOT the 1–2 Hz the literature (25 Hz hardware) reports.** Talking is dominated by <1 Hz head-bob. Design features around the **2–4 Hz chewing band**. (n=1 so far — re-validate the band on other users' data.) Tooling: `analysis/separability.py`.

- [ ] ~3–4 s sliding windows (≈ 150–200 samples at 50 Hz).
- [ ] z-score normalize per window.
- [ ] Features: time-domain (mean/var/energy/zero-cross) + **frequency-domain (FFT band ~2–4 Hz = chewing fingerprint; ratio of 2–4 Hz to 0.3–1 Hz energy is the strongest single discriminator found so far)**.
- [ ] **Random Forest** or small **SVM**. Runs trivially on-device.
- [ ] **Two-stage:** (eat / not-eat) → episode aggregation (4s window → 20s bout → bouts within 2 min = episode). Documented best performer.
- [ ] Validate with leave-one-session-out on your own data.

**Exit:** A classifier that calls eating episodes reliably enough to prompt.

### Phase 3 — Product loop

**Goal:** The actual app.

- [ ] Onboarding calibration: "chew for 20 seconds" → personalize the model. (Biggest accuracy lever, clean onboarding moment — every serious wearable calibrates.)
- [ ] Background monitoring while buds worn.
- [ ] Episode detected → notification → log food metrics (calories / macros / freeform).
- [ ] Simple history view (episodes/day, timing patterns).
- [ ] TestFlight build.

**Exit:** TestFlight launch.

---

## 4. Roadmap Beyond v1

- **v2 — Drinking detection.** Mine the v1 drinking dataset. Evaluate whether 25 Hz fused motion has *anything* usable for swallows; if not, honestly park it or explore audio.
- **v2 — WHOOP integration.** Pull recovery / strain from WHOOP API, correlate with eating timing/patterns. (v1 keeps WHOOP as conceptual analogy only.)
- **Later — Food-type hints.** Survey work shows motion+audio can classify state (solid/liquid/semi-liquid) and texture (crunchy/soft). Stretch; needs audio modality.
- **Later — Cloud model.** Aggregate opted-in user data → general model that reduces calibration burden. TS/Bun backend territory.

---

## 5. Success Criteria (v1)

- Detects a real meal as an eating episode **reliably enough to prompt** (not perfect quantification).
- Per-user calibration measurably beats cold-start.
- Notification → log loop feels frictionless.
- Drinking dataset captured + at least one documented finding on its (in)feasibility.

---

## 6. Open Questions / Watchlist

- ~~Real sample rate confirmed at ~25 Hz? (Phase 0)~~ → **Resolved: 50 Hz on Pro 3** (2× expected).
- Short-snack detection — acceptable, or does it need a separate model? (Phase 1/2)
- Talking-while-walking contamination? (Phase 1)
- Background execution longevity — does iOS suspend the motion stream? Battery cost over a full day? (Phase 3)
- Calibration UX — is 20s chewing enough, or do we need multiple food textures? (Phase 3)

---

## 7. References & Source Material

Annotated list of everything referenced while scoping this project, grouped by what it's useful *for*, with a source→phase map at the end.

---

## A. Build From This (code — start here)

### AirPodsPro-Motion-Sampler — `tukuyo`
**https://github.com/tukuyo/AirPodsPro-Motion-Sampler**
The canonical `CMHeadphoneMotionManager` sample. Streams motion from AirPods Pro (1st/2nd gen), AirPods Max, AirPods 3, Beats Fit Pro and **exports to CSV** (viewable in Files app). This is the Phase 0 fork target — it already does motion stream → CSV, which is exactly the dataset-logging primitive we need. Open `AirPodsProMotion.xcodeproj` in Xcode 12+.

### workwell — `wizenheimer`
**https://github.com/wizenheimer/workwell**
Posture monitor using AirPods Pro IMU. Useful as a *reference implementation* for the real-time loop: uses `CMHeadphoneMotionManager`, low-pass filtering to reduce jitter, background-thread sensor processing, 60 FPS updates, session persistence via UserDefaults. Good model for how to structure the always-on monitoring + session tracking that Phase 3 needs. Note: it works with quaternions → Euler (pitch/roll/yaw); we care more about user acceleration + rotation rate for chewing, but the plumbing is the same.

---

## B. Apple Docs (the API contract — read carefully for constraints)

### CMHeadphoneMotionManager
**https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager**
The core API. Starts/manages headphone motion services. Push (`startDeviceMotionUpdates(to:withHandler:)`) and pull interfaces. Requires `NSMotionUsageDescription` / Motion Usage Description in Info.plist. Adopt `CMHeadphoneMotionManagerDelegate` for connect/disconnect (ear-detection) events.

### CMDeviceMotion
**https://developer.apple.com/documentation/coremotion/cmdevicemotion**
What you actually get per sample: **attitude, rotation rate, user acceleration** (gravity-separated). This is fused/processed — there is NO raw accel/gyro from AirPods. `SensorLocation` tells you left vs right bud.

### What's new in Core Motion — WWDC23 (session 10179)
**https://developer.apple.com/videos/play/wwdc2023/10179/**
Critical constraints live here:
- `CMMotionManager` max frequency = **100 Hz** (but this is on-device; headphone streams lower, ~25 Hz in practice).
- `CMBatchedSensorManager` = 800 Hz accel / 200 Hz device motion BUT **Apple Watch only + requires active HealthKit workout**. Does NOT apply to AirPods. Don't design around it.
- `CMHeadphoneMotionManager` came to macOS 14 this year (in addition to iOS/iPadOS 14+).
- Ear-detection: buds out → disconnect event; in → connect event.

### WWDCNotes mirror of the above (faster to skim)
**https://wwdcnotes.com/documentation/wwdc23-10179-whats-new-in-core-motion/**
Text version of session 10179. Confirms the 100 Hz vs batched 800/200 Hz split and the workout-session requirement for batched. Good quick reference.

---

## C. The Feasibility Evidence (why chewing detection works)

### A Comparison between Audio and IMU data to Detect Chewing Events (eSense) — Lotfi, Tzanetakis, Eskicioglu, Irani (2020, AH'20)
**https://hci.cs.umanitoba.ca/Publications/details/a-comparison-between-audio-and-imu-data-to-detect-chewing-events-based-on-a**
ResearchGate (incl. generalization caveat): **https://www.researchgate.net/publication/341692810**
Headline: **in-ear IMU = 95% accuracy, beats audio; fusion = 97%.** BUT the same group's follow-up flags that IMU-from-earbuds has **limited generalizability for short/sporadic chewing on unseen users**, and **personalization matters** — this is the single most important caveat for our build. Drives the per-user calibration decision.

### EarBit: Using Wearable Sensors to Detect Eating Episodes in Unconstrained Environments
**https://pmc.ncbi.nlm.nih.gov/articles/PMC6101257/**
Behind-the-ear IMU is "essentially a chewing sensor." **93% accuracy / 80.1 F1** chewing @ 1s resolution. In an *outside-the-lab* 45-hour, 10-participant study it recognized all-but-one eating episode (1 min delay). Strongest evidence that this works in the wild, not just in lab. Good source for the episode-aggregation approach.

### A Survey of Earable Technology: Trends, Tools, and the Road Ahead (2025)
**https://arxiv.org/html/2506.05720v1** (HTML) · **https://arxiv.org/pdf/2506.05720** (PDF)
The big-picture map. Section 5.1 (Eating Monitoring) covers the progression from chew detection → chew count → food classification. Documents **IMChew** (91% acc/F1, 9.5% MAPE chew count, LOSO n=8) and **BiteSense** (food classification: solid/liquid/semi-liquid, texture, cooking method). Also covers BrushBuds (toothbrushing, 84.3%) as adjacent prior art. Use for v2+ roadmap (food typing) and to understand the state of the art.

### Recent Trends in Food Intake Monitoring using Wearable Sensors
**https://arxiv.org/pdf/2101.01378**
Source for the **standard pipeline**: 4s window = chewing, 20s window = chewing bout, bouts within 2 min = eating episode (Chun et al.). Also surveys headband/accelerometer muscle-contraction approaches that classify eating vs speaking/sitting/standing/walking/drinking/coughing. Good for feature + windowing design (Phase 2).

### Human activity recognition using earable device (eSense)
**https://www.researchgate.net/publication/335770433**
Directly relevant: classifies **speaking, eating, head nodding, head shaking, stay, walk, speaking-while-walking** from eSense accel+gyro using statistical features. This is the talking-vs-eating discrimination evidence, and a feature-engineering reference for Phase 2.

---

## D. The Hard-Edge Evidence (drinking / swallowing — why it's v2)

### sEMG-based automatic characterization of swallowed materials
**https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11100060/**
Why drinking is hard: reliable swallow/fluid characterization in the literature leans on **throat microphones, sEMG at the larynx, strain sensors** — not ear IMUs. One referenced study hit ~80% fluid-volume accuracy for 5–15 ml *with a throat mic*. We have none of that. Justifies deferring drinking detection.

### A Novel Wearable Device for Food Intake and Physical Activity Recognition
**https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4970114/**
Two-stage classification (food intake + activity) with SVM + decision tree → 99.85% F1. BUT note: uses a **piezoelectric strain sensor against the throat** plus accelerometer. Reinforces that the best numbers come from throat-adjacent sensing. Good for the *two-stage architecture* idea even though the sensors differ.

### I Hear You Eat and Speak (iHEARu-EAT database)
**https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4866718/**
Audio-based eating-condition recognition. Binary eat/not-eat from audio is "easily solved" (>90% recall) independent of speaking. Relevant only if we add the **audio modality** later (v2 food typing / drinking). Public dataset for research use.

---

## E. Context / Prior Art (the viral hook)

### Posture Pal — Jordi Bruin
App Store: **https://apps.apple.com/us/app/posture-pal-improve-alert/id1590316152**
Press kit: **https://impresskit.net/d3e4bea7-fdd2-465a-af7f-7d763e1a9250**
9to5Mac: **https://9to5mac.com/2022/03/17/posture-pal-iphone-app-airpods/**
The OG "AirPods motion = useful product" proof. Background operation, sensitivity levels, runs while audio plays. The whole "data is just sitting there unused" thesis. Our north star for *product framing* (passive, low-friction, no new hardware).

### The recent viral posture/pomodoro post
**https://x.com/om_patel5/status/2068158200906489958**
The thing that's hot right now — vibe-coded pomodoro + posture tracker on AirPods motion. Confirms the timing/zeitgeist for a launch. "No new permission, no extra battery, the data is just sitting there unused."

### UpRight — Posture Coach (competitor reference)
**https://apps.apple.com/us/app/upright-posture-coach/id6747097271**
Shows the productized version: live score 0–100, daily/weekly dashboards, calibration step, subscription pricing ($24.99/yr). Useful as a **monetization + UX template** for what a polished AirPods-IMU app looks like on the store.

---

## Quick Map: source → phase

- **Phase 0 (spike):** A (both repos), B (all Apple docs)
- **Phase 1 (dataset):** A (Motion-Sampler), C (survey for what to label)
- **Phase 2 (classifier):** C (Recent Trends pipeline, eSense HAR features, Lotfi), D (two-stage architecture)
- **Phase 3 (product):** A (workwell loop), B (background/ear-detection), E (UX/monetization)
- **v2 (drinking/food-type/WHOOP):** C (survey food typing), D (all), E (iHEARu audio)
