# Fitty BETA

True-physics AR clothing fitter. Scan a real garment (front, optional back), keep a wardrobe of up to 30 pieces on this device, and drape the photo on a C++ PBD/XPBD cloth sheet over ARKit body tracking.

There is no catalog of other people’s clothes, no networking, no payments, and no accounts. Physics never runs on the main thread (`com.junholee.Fitty.pbd`).

The project was authored on Linux and **has not been compiled on a Mac**. Open `Fitty.xcodeproj` in Xcode 16+ (iOS 18 SDK, deployment 17.0), pick a development team, and build. Simulator: Onboarding (if needed) → Home → Scan → **Choose photo** → kind picker → Try on (T-pose debug rig). Try on is disabled until a garment is scanned.

**Version 0.2.0. Beta**

## Product flow

```
Onboarding (first launch: 3 boxy pages, skip / don’t show again)
Home (cream canvas)
  ├─ Scan clothing  → camera / PHPicker, optional 3-2-1, front then optional back
  │                    Vision subject lift → kind picker → Documents/Garments/<uuid>/
  ├─ Wardrobe       → select, rename, notes, kind, delete, sort, Front / Front+Back badge
  ├─ Settings       → quality, haptics, countdown, debug, units, language, fabric, height
  └─ Try on         → AR + PBD/XPBD, fabric / size / wind / fit, snapshot, ReplayKit clip, A/B
                       (disabled on Home until the wardrobe has a scan)
```

## 25 big features

| # | Feature | Where |
| --- | --- | --- |
| 1 | Wardrobe of saved garments, select for try-on, persist `Documents/Garments` | `GarmentStore.swift`, `WardrobeView.swift` |
| 2 | Front + back scan. Try-on uses an atlas in U + duplicated reversed triangles (`faceCulling = .back`). RealityKit PBR cannot bind different textures per face, so this is the documented path — not two-sided PBR. | `ScanView.swift`, `ClothMeshEntity.swift`, `ImageIOSupport.swift` |
| 3 | Kinds tee / tank / hoodie / dress / pants. Pinning: tee/hoodie shoulder row; pants hip row kinematic; dress shoulders + longer V; tank narrower U. Picker on scan confirm. | `AppSettings.swift` (`GarmentKind`), `ClothSolver.cpp` (`PinMode`), `ScanView.swift` |
| 4 | Fabric presets cotton / silk / denim / knit / linen → C++ mass/damping/stretch/shear/bend/friction/XPBD α **and** Swift PBR roughness/metallic. Settings + try-on HUD. | `AppSettings.swift` (`FabricPreset`), `ClothSimulationComponent.swift`, `ContentView.swift` |
| 5 | Size XS–XXL uniform scale on rest width/length (clamped). HUD segmented control. | `GarmentSize`, `ClothSolver::setSizeScale`, `ContentView.swift` |
| 6 | XPBD stretch with compliance α so stiffness is less iteration-count dependent. Shear/bend stay classic PBD. Documented in `ClothSolver.hpp`. | `ClothSolver.cpp` `projectDistanceConstraints` |
| 7 | World-space wind + mild hash noise, Verlet acceleration. HUD slider + direction. | `ClothSolver::setWind`, `ContentView.swift` |
| 8 | Self-collision spatial hash; non-adjacent particles closer than 0.7×spacing are separated. Skipped if count > 1600. | `ClothSolver::collideSelf` |
| 9 | Chest + hip volume ellipsoids in addition to bone capsules, from `BodyCapsuleRig`. | `BodyCapsuleRig.volumeEllipsoids`, `ClothSolver::setVolumeEllipsoids` |
| 10 | Arm pins: side-column particles softly attracted to upper-arm capsules. Sleeve approximation, not a second mesh (commented in the solver). | `ClothSolver::applyArmPins` |
| 11 | ARKit light estimate → directional light + slight PBR emissive. Simulator fallback 1400 white. | `ARViewController.swift` `applyLightEstimate` |
| 12 | Snapshot: boxy button → `ARView.snapshot` → `Documents/Snapshots` → share sheet. No Photo Library write. | `ContentView.swift`, `ARClothHostController.handleSnapshot` |
| 13 | Compare A/B with ≥2 garments, swaps texture + aspect + kind without leaving AR. | `ContentView.swapAB` |
| 14 | Fit sliders length (V), tightness (U / stretch), drape (bend). Live on the sim thread. | `ClothSolver::setFit`, `ContentView.swift` |
| 15 | Onboarding, 3 boxy pages (Scan flat / Stand in frame / Drape). Skip + UserDefaults. | `OnboardingView.swift`, `FittyApp.swift` |
| 16 | Settings: quality, haptics, units, language, debug overlay, reset onboarding, fabric default. | `SettingsView.swift`, `AppSettings.swift` |
| 17 | Sim quality Low 16×20 / Med 24×32 / High 32×40. Rebuilds solver + mesh (entity swap on main; solver on `com.junholee.Fitty.pbd`). | `SimQuality`, `ClothSimulationComponent.rebuildQualityOnSimThread` |
| 18 | English + Korean via `L10n.swift` + `en.lproj` / `ko.lproj`. Device language, in-app override. | `L10n.swift`, `AppSettings.language` |
| 19 | VoiceOver labels, Dynamic Type on menus, Reduce Motion skips flash/countdown animation. | Scan / Home / Settings / HUD |
| 20 | Camera-denied screen with Open Settings; Vision fail still confirms full frame; disk-full toast. | `ScanView.swift`, `GarmentIsolator.swift`, `GarmentStore.swift` |
| 21 | ReplayKit `RPScreenRecorder.startRecording`, ~8 s, share via preview. Mic off. Permission deny toast. | `ClipRecorder.swift` |
| 22 | Height calibration 150–200 cm stepper. Scales capsule radii and rest garment size. Persisted. | `AppSettings.heightCm`, `BodyCapsuleRig` scale, `setBodyScale` |
| 23 | Debug overlay toggle: capsule proxies + sim Hz + particle count + quality. Off by default. | `AppSettings.debugOverlay`, `ARClothHostController.setDebugVisible` |
| 24 | Persistence: settings + last selected garment + last fabric/size survive cold start. | `AppSettings`, `GarmentStore.selectedID` |
| 25 | Garment metadata editor: kind, notes, date; used at try-on. | `GarmentEditorView`, `WardrobeView.swift` |

## 20 small updates

| # | Update | Where |
| --- | --- | --- |
| S1 | App icon: cream field, boxy gold “F”, 1024 PNG | `Assets.xcassets/AppIcon.appiconset` |
| S2 | Cream launch screen (`UILaunchScreen` + `LaunchBackground`) | `Info.plist`, `LaunchBackground.colorset` |
| S3 | Empty wardrobe illustration + copy (not lorem) | `WardrobeView.swift` |
| S4 | Delete garment with confirm | `WardrobeView.swift` |
| S5 | Rename garment | `WardrobeView.swift` |
| S6 | Sort wardrobe newest / name | `WardrobeView.swift`, `AppSettings.wardrobeSort` |
| S7 | Haptics on shutter, confirm, snapshot (honours settings) | `Haptics.swift` |
| S8 | Optional 3-2-1 scan countdown | `ScanView.swift`, settings |
| S9 | Reticle corner ticks (boxy L shapes) | `FittyTheme.ReticleTicks` |
| S10 | Transient toast for errors/success | `ToastCenter.swift` |
| S11 | Version 0.2.0 in plist + settings footer | `project.pbxproj` `MARKETING_VERSION`, `SettingsView` |
| S12 | `.gitignore` xcuserdata, DerivedData, `.DS_Store` | `.gitignore` |
| S13 | PNG/JPEG size cap on save (max dim 1600, ~1.4 MB) | `ImageIOSupport.swift` |
| S14 | Wardrobe cap 30; oldest evicted with notice | `GarmentStore.maxCount` |
| S15 | HUD respects safe area + landscape | `ContentView.swift` `GeometryReader` |
| S16 | Status bar dark content on cream; hidden on AR | `Info.plist`, `ARClothHostController.prefersStatusBarHidden` |
| S17 | Boxy button pressed state dim 0.85 | `BoxyButtonStyle` |
| S18 | Thumbnail badge Front / Front+Back | `HomeView`, `WardrobeView` |
| S19 | Rescan from try-on keeps the wardrobe entry (updates photos) vs **New garment** | `ScanView.rescanID`, `GarmentStore.updatePhotos` |
| S20 | This README | `README.md` |

## Theme

`FittyTheme.swift` is the single source of truth.

| Token | RGB | Use |
| --- | --- | --- |
| canvas | (0.99, 0.96, 0.88) | cream / slight yellow |
| ink | (0.17, 0.15, 0.11) | text, 2 pt strokes |
| accent | (0.82, 0.68, 0.22) | muted gold, primary fill / reticle |
| panel | canvas @ 0.92 | HUD over AR passthrough |

Buttons: `RoundedRectangle(cornerRadius: 2)`, 2 pt ink or accent stroke, pressed opacity 0.85. No `Capsule`, no corner radius 14+. System font.

## Architecture

```
SwiftUI (Onboarding / Home / Scan / Wardrobe / Settings / Try-on HUD)
  → DeviceProfile (thermal / Low Power / iPhone quality)
  → GarmentStore (Documents/Garments/<uuid>/{front.png, back.png, meta.json})
  → ARClothHostController (ARView, light estimate, snapshot)
      → BodyCapsuleRig (capsules + chest/hip ellipsoids + upper-arm capsules)
      → ClothSimulationComponent
            serial queue com.junholee.Fitty.pbd
              ClothSolverBridge.mm → ClothSolver.cpp (PBD + XPBD stretch)
            main/render thread ← positions/normals → ClothMeshEntity (PBR + atlas)
```

**Units:** meters, seconds, ARKit world space (Y-up). Joints: `bodyAnchor.transform * skeleton.modelTransform(for:)`. Gravity `(0, -9.81, 0)`.

**Threading:** the C++ solver is touched only from `com.junholee.Fitty.pbd`. Vertex upload and RealityKit stay on the main/render thread. Vision subject lift runs on a `userInitiated` queue. No C++ exceptions cross the bridge.

**Scan isolation (unchanged, required types):**

- `VNGenerateForegroundInstanceMaskRequest`
- Result `as? VNInstanceMaskObservation`
- `generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)`
- Fallback: full original frame; user can still confirm
- PHPicker stays permission-free (no `NSPhotoLibraryUsageDescription`)

## Physics / bridge

Explicit methods (no unnamed magic):

- `setConfig(mass:damping:stretch:shear:bend:friction:)`
- `setPhotoAspect`
- `setWind(x:y:z:)`
- `setXPBDCompliance`
- `enableSelfCollision`
- `setVolumeEllipsoids` (12 floats: center, radii, U, V)
- `setQuality(width:height:spacing:)` (Swift may also reconstruct)
- `setPinMode` / `setSizeScale` / `setFit` / `setBodyScale` / `setArmCapsules`

XPBD stretch: `Δλ = (−C − α̃ λ) / (w + α̃)`, `α̃ = α / Δt²`. `α = 0` is a hard constraint. Shear and bend remain classic PBD.

## iPhone

Universal iPhone + iPad (`TARGETED_DEVICE_FAMILY = 1,2`, `UIRequiresFullScreen`). Cream/ink/gold and boxy 44 pt controls stay. Physics stays on `com.junholee.Fitty.pbd`. Policy lives in `DeviceProfile.swift`.

- **Default quality:** iPhone Low 16×20, iPad Med 24×32. Settings can still raise it. `DeviceProfile.effectiveQuality` then applies thermal / Low Power / slow-sim step-down.
- **Thermal + Low Power:** fair/serious/critical or Low Power Mode drops quality one step, caps wind, turns off self-collision, and skips ReplayKit. Toast once. If sim Hz stays under ~25, quality drops one more step once per session unless the user locked quality.
- **Background:** `scenePhase` + `UIApplication` notifications pause the C++ solver and the AR session. Foreground resumes tracking.
- **Textures:** GPU albedo max 1024 px on iPhone, 2048 on iPad (`ImageIOSupport.cappedForTexture`). Disk PNGs still cap at 1600.
- **Layout:** try-on hides the nav bar. Bottom HUD starts collapsed (size + snapshot/record/scan) and expands for fabric/fit/wind. Home primary actions sit in the thumb zone. Scan shutter is a 64 pt boxy button at the bottom.
- **AR camera:** cheapest `ARBodyTrackingConfiguration` video format with at least 30 fps; CADisplayLink preferred range 30–60. Camera grain / DoF / grounding shadows off.
- **Copy:** EN + KO in `L10n.swift` and `en.lproj` / `ko.lproj`. Settings shows live quality, thermal state, and Low Power.

## How to run — Simulator vs device

1. Open `Fitty.xcodeproj`, scheme **Fitty**, bundle id `com.junholee.Fitty`.
2. Signing: pick a team (`DEVELOPMENT_TEAM` is empty).
3. **Device (A12+ iPhone/iPad):** live `ARBodyTrackingConfiguration`. Grant camera. Stand in frame. Optional height calibration in Settings.
4. **Simulator:** overlay explains the fallback. Scan uses **Choose photo**. Try-on uses a standing T-pose capsule + ellipsoid rig ~2 m along −Z. Debug overlay (Settings) shows capsule proxies.

## How to run C++ tests

From the repo root (Linux or macOS, no Xcode required):

```
g++ -std=c++17 -O2 -IFitty/Physics \
    Fitty/Physics/ClothSolver.cpp \
    Tests/ClothSolverTests.cpp \
    -o /tmp/cloth_tests
/tmp/cloth_tests
```

Last run (Debian, g++ 14.2, 2026-08-31 NZST): **51 passed, 0 failed**.

Coverage includes: no NaN over 120 steps; capsule push-out; volume ellipsoid push-out; self-collision separation; wind moves COM; XPBD stable at dt=1/30; size/aspect finite bbox; denim vs silk different stretch; pants pinning finite; tank narrower / dress longer; quality rebuild 16×20 and 32×40; arm pins finite.

Tests live in `Tests/` and are **not** in the iOS target.

## Known gaps

- No Mac/Xcode/device build on this branch.
- Signing: `DEVELOPMENT_TEAM` empty.
- `TextureResource.generate(from:withName:options:)` vs async on some iOS 18 SDKs — wrap in a `Task` if needed.
- RealityKit UV origin may flip albedo vertically.
- `PhysicallyBasedMaterial.emissiveColor` / `Opacity.init(scale:texture:)` may differ by SDK.
- Vision subject lift is weaker in Simulator; confirm still accepts the full frame.
- Capsules + two ellipsoids are still an inner hull; fitted dresses can clip.
- Arm pins are a sleeve approximation, not a second mesh.
- ReplayKit records the whole screen (system HUD included), not an isolated ARView framebuffer.
- Classic PBD shear/bend stiffness is still iteration-count dependent; only stretch is XPBD.
- `MeshResource(from: LowLevelMesh)` sync vs async, `Entity.init()` isolation — same notes as the scaffold.

## License

Private prototype. All rights reserved.
