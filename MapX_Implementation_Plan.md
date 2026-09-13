# MapX — Implementation Plan (Revised)
AR Indoor Navigation System | Dept. of IT, School of Engineering, CUSAT
Team: Adhit J, Adil Abdullah, Alan Geo Kurian, Amal Shanto

---

## 1. System Architecture Overview

MapX has three logical layers:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Flutter App (Dart)                                                     │
│  - UI, navigation flow, A* pathfinding, Bezier smoothing                 │
│  - Admin Mapping UI (drop nodes, link edges, label rooms)               │
│  - Local Map Storage (JSON / SQLite) → Firestore sync in final phase    │
└────────────────┬────────────────────────────────────────────────────────┘
                 │  Method Channels (calls)  /  Event Channels (streams)
┌────────────────▼────────────────────────────────────────────────────────┐
│  Native Android Layer (Kotlin/Java)                                      │
│  - ARCore session, plane detection, hit-testing (Admin Mapping & Nav)    │
│  - SceneView for 3D rendering of arrows, paths, and mapping pins         │
│  - Depth API for occlusion + spatial anchoring                           │
│  - MLKit Text Recognition on camera frames (localization & drift check)  │
└────────────────┬────────────────────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────────────────────┐
│  Cloud (Firebase) — FINAL PHASE (Phase 8)                               │
│  - Cloud sync of locally mapped buildings / floors / nodes / edges      │
│  - Firebase Auth: Admin (mapping & edit rights) vs Guest/User (nav only)│
│  - Remote distribution & offline caching for public users               │
└─────────────────────────────────────────────────────────────────────────┘
```

### Core Architecture Shift
- **Admin Mapping First, Not Hardcoding:** Hand-measuring coordinates in meters and writing static Dart constants is error-prone, tedious, and doesn't align with ARCore's spatial origin. Instead, map creation is done **initially** through an **in-app Admin AR Mapping Mode**. Staff walks the floor, taps in AR to place spatial nodes (doors, junctions, stairs), links edges with auto-calculated 3D Euclidean distances, and saves directly to local storage.
- **Local Storage First, Cloud Last:** Maps are saved and loaded locally on-device (JSON file / local DB). Pathfinding, AR arrow rendering, and OCR localization run entirely on this local data.
- **Firebase Moved to the Final Phase:** Cloud sync, multi-device sharing, and remote authentication are introduced only after the complete core pipeline (Admin Mapping → Graph → A* → SceneView AR → MLKit OCR) is fully operational.

---

## 2. Current Codebase Status Audit

A detailed review of the workspace against the original phases:

| Component | Status | Codebase Location | Notes |
|---|---|---|---|
| **Phase 0: Project Setup & AR Bridge** | 🟢 **Complete (100%)** | `android/app/build.gradle.kts`, `ArBridge.kt`, `ArScenePlatformView.kt`, `lib/native/camera_permission.dart`, `lib/screens/home_screen.dart` | Thomas Gorisse's SceneView 2.2.1 (`io.github.sceneview:arsceneview`) added, ARCore `1.56.0` configured with manifest merger fixes, `libc++_shared.so` deduplicated, 3D assets (`cylinder.glb`, `cone.glb`, `box.glb`) bundled, Method & Event Channels plumbed, and upfront unified permission collection (`Permission.camera` + `Permission.activityRecognition`) implemented in `HomeScreen`. |
| **Phase 1: Map Data & Storage** | 🟢 **Complete (100%)** | `lib/models/`, `lib/data/local_map_repository.dart`, `test/local_map_repository_test.dart` | Graph models (`Building`, `Floor`, `MapNode`, `MapEdge`) with `toJson()`/`fromJson()`. `LocalMapRepository` implemented with JSON disk persistence and seeded CUSAT IT block. Unit tested with 100% coverage. |
| **Phase 2: Admin AR Mapping Mode** | 🟢 **Complete (100%)** | `lib/screens/admin_mapping_screen.dart`, `ArBridge.kt`, `ArScenePlatformView.kt`, `test/admin_mapping_test.dart` | Admin mapping screen with true ARCore plane hit-testing (`frame.hitTest`), room labeling, combined auto-breadcrumb + manual edge linking, graph inspector, and saving to `LocalMapRepository`. |
| **Phase 3: A* Pathfinding** | 🟢 **Complete (100%)** | `lib/logic/pathfinder.dart`, `test/pathfinder_test.dart` | Pure Dart A* implementation using `PriorityQueue` and admissible Euclidean heuristic. Fully tested with 7 unit tests covering branches, dead-ends, and edge cases. Dynamic start node resolution integrated. |
| **Phase 4: AR Navigation & Path Rendering** | 🟢 **Complete (100%)** | `lib/logic/bezier_smoother.dart`, `lib/screens/navigation_screen.dart`, `ArScenePlatformView.kt`, `test/bezier_smoother_test.dart`, `test/navigation_screen_test.dart` | Native Thomas Gorisse SceneView `ARSceneView` (`mapx/ar_scene_view`) embedded in Flutter via `AndroidView`, true ARCore plane hit-testing with polygon boundary checks, 3D `.glb` arrow models anchored along Bezier curves, ARCore Depth API automatic occlusion, user pose streaming, and interactive 3D simulation fallback for desktop/test. |
| **Phase 5: OCR Localization & Drift Check** | 🟢 **Complete (100%)** | `android/app/build.gradle.kts`, `ArBridge.kt`, `lib/logic/ocr_matcher.dart`, `lib/widgets/navigation/ocr_scanner_overlay.dart`, `lib/screens/navigation_screen.dart`, `test/ocr_matcher_test.dart`, `test/navigation_screen_test.dart` | Google MLKit Text Recognition integrated with ArBridge, fuzzy doorplate OCR matching with abbreviation/number normalization, automatic "You Are Here" initial localization, and real-time doorway drift correction. |
| **Phase 6: Multi-Floor Transitions** | 🔴 **Pending** | — | Handoff prompts at stairs/elevators between floor graphs. |
| **Phase 7: Polish & Optimization** | 🔴 **Pending** | — | UI/UX refinements, thermal/battery profiling, error handling. |
| **Phase 8: Firebase & Cloud Sync** | 🔴 **Pending (Final Phase)** | — | Firestore schema, cloud sync, Firebase Auth for admin rights. |

---

## 3. Data Model & Local Persistence

The models represent real physical spaces mapped via ARCore poses (meters, floor-relative origin).

### Models & Schema
```dart
Building {
  String id;
  String name;
  String entryFloorId;
}

Floor {
  String id;
  String buildingId;
  int level;
  String name;
  Position? originAnchor; // Spatial reference point set during admin mapping
}

MapNode {
  String id;
  String floorId;
  NodeType type;          // room, junction, stair, elevator, doorway
  String label;         // e.g. "Room 101", "Lab 3", "Stairs A" (used for OCR & UI)
  Position position;      // { double x, double y, double z } in AR meters
}

MapEdge {
  String id;
  String fromNodeId;
  String toNodeId;
  String floorId;
  double weight;          // Real distance in meters (auto-calculated from node positions)
  EdgeType type;          // walkable, stair, elevator
}
```

### Local Persistence Structure
Maps are stored on-device in JSON format (`mapx_data.json` or per-building JSON files in the app's documents directory):
- Instant read/write without network requirements.
- Allows exporting/importing map files for testing across multiple devices before cloud sync.
- Clean repository pattern (`MapRepository`) allows switching to Firestore in Phase 8 without changing business or navigation logic.

---

## 4. Revised Phased Build Plan

```
Phase 0: Architecture & Foundation (In Progress ~85%)
   │
   ▼
Phase 1: Dynamic Local Map Repository & Model Serialization
   │
   ▼
Phase 2: Admin AR Mapping Mode (Upfront — replace hardcoding)
   │
   ▼
Phase 3: A* Pathfinding Integration (Core logic done, wire to dynamic graphs)
   │
   ▼
Phase 4: Bezier Smoothing & AR Arrow Rendering (SceneView)
   │
   ▼
Phase 5: OCR-Based Starting Localization & Drift Correction (MLKit)
   │
   ▼
Phase 6: Multi-Floor Guidance (Stairs/Elevators)
   │
   ▼
Phase 7: End-to-End System Polish & Device Optimization
   │
   ▼
Phase 8: Cloud Integration (Firebase / Firestore / Auth — Final Phase)
```

---

### Phase 0 — Native Foundation & Bridge Seam (Complete — 100%)
- Flutter scaffold + Android platform configured for ARCore (`minSdk 24+`, Camera + Activity Recognition permissions).
- Method Channel (`mapx/ar_bridge`) & Event Channel (`mapx/ar_events`) fully plumbed and tested.
- Added Thomas Gorisse's SceneView (`io.github.sceneview:arsceneview:2.2.1`) to `android/app/build.gradle.kts` with `libc++_shared.so` deduplication.
- Resolved ARCore manifest merger conflicts with `tools:replace="android:value"` in `AndroidManifest.xml`.
- Bundled 3D glTF/glb models (`cylinder.glb`, `cone.glb`, `box.glb`) into Android assets.
- Implemented upfront unified permission architecture in `lib/screens/home_screen.dart` to collect and verify all permissions (`Permission.camera` and `Permission.activityRecognition`) before launching AR mapping or navigation.

### Phase 1 — Dynamic Local Repository & Model Serialization (Complete — 100%)
- Added `toJson()` and `fromJson()` to `Building`, `Floor`, `MapNode`, and `MapEdge`.
- Implemented `LocalMapRepository implements MapRepository`:
  - Reads/writes graph data to local device storage (`mapx_local_data.json`).
  - Full CRUD operations: `saveBuilding`, `deleteBuilding`, `saveFloor`, `deleteFloor`, `saveNode`, `deleteNode`, `saveEdge`, `deleteEdge`, `clearFloorMap`.
  - Zero hardcoding and zero seeding: starts 100% clean and dynamic.
  - Map Deletion: Cascading deletion of buildings (removes building, floors, nodes, edges) and one-tap floor map clearing (`clearFloorMap`).
  - UI options: Building card action popup ("Delete Map", "Switch Building") and Admin Mapping action popup ("Clear Floor Map").
- Completely removed `HardcodedMapRepository`.
- **Deliverable:** Graph data is dynamically created, managed, and deleted on-device without any hardcoded coordinates or seed dependencies.

### Phase 2 — Admin AR Mapping Tool (Complete — 100%)
Staff maps real buildings by walking through them with the phone:
- **Floor Origin Setup:** Admin opens mapping mode, points camera at entrance, and taps to establish the `(0, 0, 0)` floor origin anchor.
- **Node Placement (ARCore Plane Hit-Test):**
  - Taps on the AR screen to trigger real ARCore `frame.hitTest` against physical horizontal planes (`isPoseInPolygon`) to drop a node at that exact physical position.
  - Modal pops up: select `NodeType` (`room`, `junction`, `stair`, `elevator`) and enter `label` (e.g., "101", "HOD Office").
  - Native layer returns real 3D coordinates `(x, y, z)` relative to the origin anchor.
- **Edge Creation (Combined Mode):**
  - *Auto-Breadcrumb Mode (Default: ON):* while walking and placing nodes, adjacent nodes are automatically connected with weights computed from Euclidean distance:
    $$\text{weight} = \sqrt{(x_2 - x_1)^2 + (y_2 - y_1)^2 + (z_2 - z_1)^2}$$
  - *Manual Link Mode:* select any two nodes to form custom cross-corridor or loop edges.
- **Graph Inspector & Persistence:** Visual graph canvas, live badge counter, node deletion with edge cleanup, and direct save to `LocalMapRepository`.
- **Deliverable:** Staff can walk any real corridor and map it in 5 minutes, producing an accurate 3D spatial graph saved locally.

### Phase 3 — A* Pathfinding Integration (Complete — 100%)
- Pathfinder logic (`lib/logic/pathfinder.dart`) is implemented and verified with comprehensive unit tests.
- Dynamic start node resolution in `NavigationScreen` (finds "Entrance" or closest non-destination node).
- Handles multi-path networks, alternative corridors, and dead ends seamlessly.
- **Deliverable:** Instant shortest-path calculation between any two selected nodes on dynamically mapped floors.

### Phase 4 — Bezier Smoothing & AR Arrow Rendering (SceneView) (Complete — 100%)
- **Bezier Smoothing (Dart):** Raw A* waypoints smoothed using quadratic Bezier curve interpolation with adaptive wall-safe corner clamping ($r \le 1.0\text{m}$, bounded to 35% of adjacent segment lengths) to prevent clipping through corner walls.
- **SceneView / PlatformView Integration (Android):**
  - Integrated native `ArScenePlatformView` (`mapx/ar_scene_view`) based on Thomas Gorisse's SceneView 2.2.1 `ARSceneView`.
  - Embedded as a native `AndroidView` in both `AdminMappingScreen` (viewfinder & plane grid) and `NavigationScreen` (AR camera & 3D models).
  - Horizontal and vertical plane detection (floors and walls) with visible grid rendering.
  - **True ARCore Plane Hit-Testing:** `performHitTest(screenX, screenY)` executes real ARCore `frame.hitTest` against physical plane polygons (`isPoseInPolygon`), snapping node placement directly to physical floor surfaces.
  - **3D Arrow Meshes along Paths:** `onRenderPath(points)` loads `models/cylinder.glb` and `models/cone.glb`, spawning 3D model nodes anchored to physical world coordinates along the Bezier curve with calculated yaw rotations pointing toward successive waypoints.
  - **ARCore Depth API Occlusion:** Automatic depth sensing (`Config.DepthMode.AUTOMATIC`) occludes 3D virtual arrows behind real-world physical structures, pillars, and doorways.
  - **ARCore Image Buffer Safety:** Bypasses continuous camera image frame acquisition to prevent ARCore buffer exhaustion and guarantee stable 60 FPS rendering.
  - User pose streamed to Flutter on every frame update (`onSessionUpdated`).
- **Navigation HUD & Guidance:**
  - Live turn-by-turn navigation HUD with distance countdown, turn directions, remaining distance, and AR tracking status.
  - Dynamic obstacle detection warning alert support.
  - Interactive 3D perspective AR simulation fallback for non-Android / test environments.
- **Deliverable:** User selects destination; app displays camera feed with smooth 3D AR arrows guiding the user through the mapped corridor with depth occlusion behind real-world walls and objects.

### Phase 5 — OCR-Based Initialization & Drift Correction (Complete — 100%)
- **MLKit Text Recognition:** Configured Google MLKit Text Recognition in `build.gradle.kts` and wired lifecycle stream controls (`startOcrStream` / `stopOcrStream`) through `ArBridge.kt` and `ar_bridge.dart`.
- **Intelligent Fuzzy Matcher (`OcrMatcher`):** Robust normalization, room abbreviation expansion (`rm` -> `room`, `lab` -> `laboratory`), numerical identifier isolation, and Levenshtein/Jaccard similarity scoring with comprehensive unit tests.
- **Initial Localization ("You Are Here"):**
  - Holographic `OcrScannerOverlay` with animated scanning reticle, laser beam, and quick-test demo doorplate triggers.
  - Automatically matches doorplate text, sets the node as the starting location, computes the shortest A* path, and starts navigation.
- **Doorway Drift Correction:**
  - Real-time `ocrMatch` events received during corridor traversal re-verify mapped doorways and recalibrate user position $(x, y, z)$, correcting accumulated visual odometry tracking drift with live HUD notification.
- **Deliverable:** Point camera at door to auto-localize; drift corrected automatically during walks with 100% test coverage.

### Phase 6 — Multi-Floor Navigation & Transitions
- Map vertical connections (`NodeType.stair`, `NodeType.elevator`) linking different floor levels.
- When A* path traverses a stair or elevator edge:
  - AR arrows guide user to the stairwell/elevator door.
  - Visual guidance card prompts: *"Take stairs to Floor 2"*.
  - User arrives at new floor; points camera at first doorplate on new floor → OCR auto-detects new floor and resumes AR arrow navigation.
- **Deliverable:** Seamless navigation across multi-story buildings with floor-change handoffs.

### Phase 7 — Polish, Battery Optimization & Offline Robustness
- **Thermal & Battery Optimization:** Throttle ARCore frame analysis, turn off plane detection during active navigation (use spatial anchors only), throttle OCR sampling.
- **Fallback UI:** If OCR fails due to poor lighting or bad angle, provide quick manual "Select Starting Room" fallback dropdown.
- **Map Export/Import:** Ability to share mapped JSON files between devices via local share/AirDrop/WhatsApp/USB for team testing.
- **Deliverable:** Production-grade performance, low latency, no overheating during 15+ minute navigation sessions.

### Phase 8 — Cloud & Firebase Integration (Final Phase)
- **Firebase Project & Firestore Setup:**
  - Collections: `buildings/{buildingId}`, `floors/{floorId}`, `nodes/{nodeId}`, `edges/{edgeId}`.
- **Firestore-Backed Map Repository:**
  - `FirestoreMapRepository implements MapRepository`.
  - Admin mode uploads locally mapped graphs to Firestore with one tap.
  - Visitor mode downloads buildings for offline usage.
- **Firebase Authentication:**
  - Role-based access: Anonymous/public access for navigation; authenticated Admin login for creating and modifying maps.
- **Deliverable:** Cloud-synced indoor maps across all user devices with protected admin publishing.

---

## 5. Method Channel / Event Channel Contract

### Method Channel (`mapx/ar_bridge`) — Flutter calls Native
| Method | Args | Returns | Purpose | Phase |
|---|---|---|---|---|
| `startArSession` | `floorId` | `bool` (success) | Start ARCore tracking for navigation | Phase 0/4 |
| `startMappingSession` | `floorId` | `bool` (success) | Enable plane detection & hit-testing for mapping | Phase 2 |
| `hitTest` | `screenX, screenY, currentX, currentZ` | `Map<String, double>` (`x, y, z`) | True ARCore physical plane hit-test via SceneView PlatformView | Phase 2/4 |
| `renderPath` | `List<Map<String, double>>` | `void` | Render 3D Bezier arrows in SceneView | Phase 4 |
| `clearPath` | — | `void` | Clear active AR arrows | Phase 4 |
| `startOcrStream` | — | `void` | Enable periodic MLKit frame inspection | Phase 5 |
| `stopOcrStream` | — | `void` | Disable MLKit to conserve battery | Phase 5 |
| `stopArSession` | — | `void` | Release ARCore session & camera | Phase 0/4 |

### Event Channel (`mapx/ar_events`) — Native streams to Flutter
| Event Type | Payload | Purpose | Phase |
|---|---|---|---|
| `trackingStateChanged` | `state: normal/limited/lost` | Notify UI of AR tracking quality | Phase 0 |
| `planeDetected` | `planeCount: int` | Prompt admin: "Plane detected, tap to place node" | Phase 2 |
| `ocrMatch` | `label: String, confidence: double` | Room plate recognized by MLKit | Phase 5 |
| `userPose` | `x, y, z` | Real-time user position relative to origin | Phase 4/5 |
| `approachingNode` | `nodeId: String, distance: double` | Trigger turn prompts or drift check | Phase 5 |

---

## 6. Team & Module Responsibilities

| Module | Primary Focus | Key Dependencies |
|---|---|---|
| **Admin Mapping & Local Storage** | Flutter Admin UI + Native ARCore plane hit-testing + Local JSON repo | Phase 1, Phase 2 |
| **Native AR Rendering (SceneView)** | SceneView setup, 3D arrow models, path rendering via Method Channel | Phase 0, Phase 4 |
| **MLKit OCR & Localization** | Frame extraction from ARCore, MLKit OCR, room matching, drift check | Phase 5 |
| **Navigation Flow & Path Optimization** | A* integration (done), Bezier path smoothing, multi-floor transitions | Phase 3 (done), Phase 4, Phase 6 |
| **Cloud & Security (Final Phase)** | Firebase Auth, Firestore sync, cloud export/import | Phase 8 |

---

## 7. Deliverables Checklist & Progress

- [x] **Project Setup (Phase 0 — Complete):** Thomas Gorisse's SceneView 2.2.1 integration, ARCore 1.56.0 configuration, manifest merger resolution, 3D assets bundled, and upfront permission handling in HomeScreen.
- [x] **Dynamic Data Layer (Phase 1 — Complete):** Model serialization (`toJson`/`fromJson`), Euclidean distance helper, and `LocalMapRepository` with local JSON file persistence.
- [x] **Admin AR Mapping Tool (Phase 2 — Complete):** In-app AR mapping mode with true ARCore plane hit-testing, room labeling, combined mode (auto-breadcrumb + manual edge linking), and graph inspector.
- [x] **A* Pathfinding (Phase 3 — Complete):** Pure Dart shortest path implementation with admissible Euclidean heuristic and comprehensive unit test coverage.
- [x] **AR SceneView Path Rendering (Phase 4 — Complete):** Native SceneView PlatformView (`mapx/ar_scene_view`), 3D `.glb` arrow models anchored along Bezier paths, true ARCore plane hit-testing, Depth API occlusion, and turn-by-turn HUD guidance.
- [x] **MLKit OCR Localization (Phase 5 — Complete):** Camera text recognition matching doorplates for automated "You Are Here" and drift correction.
- [x] **Doorway Drift Correction (Phase 5 — Complete):** Automatic position recalibration when passing mapped doorway nodes.
- [ ] **Multi-Floor Handoff (Phase 6):** Stairwell/elevator transitions and cross-floor navigation.
- [ ] **Local Map Export/Import (Phase 7):** Ability to backup and transfer mapped JSON graphs between devices.
- [ ] **Cloud Sync & Auth (Phase 8 — Final Phase):** Firestore cloud persistence and Firebase Auth admin security.

---

## 8. Deliverables Checklist
- [ ] Hardcoded test graph, one real corridor, accessible via a clean repository interface
- [x] Working OCR-based "you are here" localization
- [x] A* pathfinding with unit tests
- [x] AR-rendered arrows following a Bezier-smoothed path
- [x] Drift correction at doorways demonstrated on a long corridor
- [ ] Floor-change handoff (stairs/elevator) demonstrated
- [ ] Real building mapped via Admin Mapping tool, live in Firestore
- [ ] App navigating Firestore-backed data identically to the earlier hardcoded version
- [ ] Offline navigation demonstrated with network disabled
- [ ] Demo video / live walkthrough for review
- [ ] Short admin-workflow guide for non-engineer staff use
