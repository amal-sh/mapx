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
| **Phase 0: Project Setup & AR Bridge** | 🟡 **Partially Complete (~85%)** | `android/app/build.gradle.kts`, `ArBridge.kt`, `lib/native/ar_bridge.dart`, `camera_permission.dart` | ARCore `1.56.0` added, Method/Event channel seam plumbed on Kotlin and Dart sides, runtime camera permissions handled, Gradle wrapper fixed to cached 8.14.1. **Pending:** SceneView rendering dependency and MLKit OCR dependency in Android build. |
| **Phase 1: Map Data & Storage** | 🟢 **Complete (100%)** | `lib/models/`, `lib/data/local_map_repository.dart`, `test/local_map_repository_test.dart` | Graph models (`Building`, `Floor`, `MapNode`, `MapEdge`) with `toJson()`/`fromJson()`. `LocalMapRepository` implemented with JSON disk persistence and seeded CUSAT IT block. Unit tested with 100% coverage. |
| **Phase 2: Admin AR Mapping Mode** | 🟢 **Complete (100%)** | `lib/screens/admin_mapping_screen.dart`, `ArBridge.kt`, `test/admin_mapping_test.dart` | Admin mapping screen with plane hit-testing, room labeling, combined auto-breadcrumb + manual edge linking, graph inspector, and saving to `LocalMapRepository`. |
| **Phase 3: A* Pathfinding** | 🟢 **Complete (100%)** | `lib/logic/pathfinder.dart`, `test/pathfinder_test.dart` | Pure Dart A* implementation using `PriorityQueue` and admissible Euclidean heuristic. Fully tested with 7 unit tests covering branches, dead-ends, and edge cases. Dynamic start node resolution integrated. |
| **Phase 4: AR Navigation & Path Rendering** | 🔴 **Pending (Next Phase)** | `lib/screens/navigation_screen.dart` | Currently has placeholder black container. Needs SceneView integration, Bezier smoothing in Dart, and AR directional arrow placement along the computed path. |
| **Phase 5: OCR Localization & Drift Check** | 🔴 **Pending** | `ArBridge.kt` (`ocrMatch` stub) | Needs MLKit Text Recognition on camera frames, fuzzy matching against mapped room labels, and AR pose anchoring. |
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

### Phase 0 — Native Foundation & Bridge Seam (Current status: ~85%)
- Flutter scaffold + Android platform configured for ARCore (`minSdk 24+`, Camera permission).
- Method Channel (`mapx/ar_bridge`) & Event Channel (`mapx/ar_events`) declared.
- **Remaining work:** Add SceneView dependencies to `android/app/build.gradle.kts`, set up native Android view or texture for AR rendering.

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
- **Node Placement (ARCore Hit-Test):**
  - Taps on the AR screen (plane hit-test) to drop a node at that exact physical position.
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

### Phase 4 — Bezier Smoothing & AR Arrow Rendering (Next Phase)
- **Bezier Smoothing (Dart):** Raw A* waypoints (straight node-to-node line segments) are smoothed using quadratic Bezier curve interpolation to prevent jagged 90-degree turns.
- **SceneView Integration (Android):**
  - Integrate SceneView / Filament in native Android.
  - Render 3D directional animated arrows floating at walking eye-level (~0.5m – 1.0m above floor) pointing toward the next waypoint.
  - As user moves forward, update proximity and clear passed arrows.
- **Deliverable:** User selects destination; app displays camera feed with smooth 3D AR arrows guiding the user through the mapped corridor.

### Phase 5 — OCR-Based Initialization & Drift Correction
- **MLKit Text Recognition:** Process ARCore camera frames periodically (throttled at ~2–3 Hz or on demand to save battery).
- **Initial Localization ("You Are Here"):**
  - User opens navigation and points camera at nearest room doorplate (e.g. "Room 102").
  - OCR extracts text; fuzzy-matches against `MapNode.label`s for the current floor.
  - On confident match, app automatically sets that node as the starting location (eliminates manual start selection).
- **Doorway Drift Correction:**
  - As the user walks past known mapped doorways, background OCR re-verifies the door label and corrects ARCore's accumulated spatial tracking drift.
- **Deliverable:** Point camera at door to start navigation; drift corrected automatically during long walks.

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
| `dropAnchorAtScreenPoint` | `x, y` | `Map<String, double>` (`x, y, z`) | Hit-test against detected plane to get 3D coords | Phase 2 |
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

- [x] **Project Setup (Phase 0):** ARCore Android configuration, permission handling, Method/Event Channel bridge foundation.
- [x] **Dynamic Data Layer (Phase 1 — Complete):** Model serialization (`toJson`/`fromJson`), Euclidean distance helper, and `LocalMapRepository` with local JSON file persistence.
- [x] **Admin AR Mapping Tool (Phase 2 — Complete):** In-app AR mapping mode with plane hit-testing, room labeling, combined mode (auto-breadcrumb + manual edge linking), and graph inspector.
- [x] **A* Pathfinding (Phase 3 — Complete):** Pure Dart shortest path implementation with admissible Euclidean heuristic and comprehensive unit test coverage.
- [ ] **AR SceneView Path Rendering (Phase 4):** 3D animated arrows following Bezier-smoothed routes in camera viewport.
- [ ] **MLKit OCR Localization (Phase 5):** Camera text recognition matching doorplates for automated "You Are Here" and drift correction.
- [ ] **Doorway Drift Correction (Phase 5):** Automatic position recalibration when passing mapped doorway nodes.
- [ ] **Multi-Floor Handoff (Phase 6):** Stairwell/elevator transitions and cross-floor navigation.
- [ ] **Local Map Export/Import (Phase 7):** Ability to backup and transfer mapped JSON graphs between devices.
- [ ] **Cloud Sync & Auth (Phase 8 — Final Phase):** Firestore cloud persistence and Firebase Auth admin security.

---

## 8. Deliverables Checklist
- [ ] Hardcoded test graph, one real corridor, accessible via a clean repository interface
- [ ] Working OCR-based "you are here" localization
- [ ] A* pathfinding with unit tests
- [ ] AR-rendered arrows following a Bezier-smoothed path
- [ ] Drift correction at doorways demonstrated on a long corridor
- [ ] Floor-change handoff (stairs/elevator) demonstrated
- [ ] Real building mapped via Admin Mapping tool, live in Firestore
- [ ] App navigating Firestore-backed data identically to the earlier hardcoded version
- [ ] Offline navigation demonstrated with network disabled
- [ ] Demo video / live walkthrough for review
- [ ] Short admin-workflow guide for non-engineer staff use
