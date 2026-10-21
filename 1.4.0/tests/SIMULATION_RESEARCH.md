# ABCCAD headset-free testing research

Researched 2026-10-02. Original project files were not modified during this research.

## Recommended approach

Use three complementary checks: deterministic Godot regressions for block types, ownership, and save/load; a graphical replay scene with simulated controller input for visual evidence; and the official Meta XR Simulator for OpenXR integration and controller/UI smoke testing. This is an engineering recommendation based on the APIs below, not a claim that a simulator session has already been run.

## Official simulator on this Mac

Meta XR Simulator is an OpenXR runtime, rather than an Android/device emulator. Its current standalone documentation supports Vulkan and Metal on macOS, but excludes OpenGL/OpenGL ES. It can drive headset and controller inputs with keyboard/mouse. Synthetic rooms provide passthrough, scene data, and anchors; environment depth is Windows-only. It therefore fits desktop testing of this project's controller actions and UI, but cannot prove Android filesystem behavior, real tracking quality, hardware performance, or headset comfort. [Meta overview](https://developers.meta.com/vr/documentation/native/xrsim-intro/)

Godot explicitly documents using Meta XR Simulator on Windows/macOS. The Godot Meta Toolkit provides an editor setup tool that configures simulator launch. Its documented flow is Project → Tools → Configure Meta XR Simulator, then select the extracted simulator. The toolkit is a convenience rather than a reason to upgrade or install plugins before trying an already installed runtime. [Godot announcement](https://godotengine.org/article/godot-xr-update-feb-2025/), [Toolkit setup](https://godot-sdk-integrations.github.io/godot-meta-toolkit/manual/xr_simulator.html)

The new standalone runtime's activation toggle changes the active runtime, including `/usr/local/share/openxr/1/active_runtime.json` on macOS, and deactivation restores the previous runtime. Check the installed version and runtime manifest before applying current instructions to an older SDK-bundled installation. A successful `hello_xr` launch is Meta's suggested runtime setup check. [Meta getting started](https://developers.meta.com/vr/documentation/native/xrsim-getting-started/)

## Programmatic input and visual replay

Godot exposes tracker registration through `XRServer.add_tracker`. `XRPositionalTracker` exposes pose updates and controller input values; controller trackers supply buttons, floats, and vectors. These are interface implementation APIs, so use them inside an explicit development simulator/harness rather than modifying production hand scripts to accept fake inputs. Confirm the available tracker class against the installed Godot version: current docs mark positional-tracker input methods deprecated in favor of `XRControllerTracker`. [XRServer API](https://docs.godotengine.org/en/4.5/classes/class_xrserver.html), [Tracker API](https://docs.godotengine.org/en/4.5/classes/class_xrpositionaltracker.html)

A custom `XRInterfaceExtension` is possible, but requires initialization, projection, transforms, and rendering callbacks. For these three defects that is unnecessary compared with a test scene using real hand scripts, real pickup components, registered test trackers, and a normal camera. [Interface extension API](https://docs.godotengine.org/en/4.5/classes/class_xrinterfaceextension.html)

There is also a third-party Godot XR Simulator addon by Cafezinhu. It selects left/right controllers with Q/E, moves them with mouse/scroll, and sends trigger/grip/buttons. This is a possible manual fallback; it is not an official Godot runtime, and compatibility needs checking before adoption. [Addon author's repository](https://github.com/Cafezinhu/godot-vr-simulator)

Meta supports recording inputs once into VRS and replaying automatically. Replay reproduces the input path but provides no pass/fail verdict; a harness must check logs, timeout, and application state. This is a useful future repeatable visual workflow after one representative hand-transfer/UI session has been recorded. [Meta automated testing](https://developers.meta.com/vr/documentation/native/xrsim-native-automated-testing/)

## Local code evidence and target checks

`1.4.0/project.godot` declares Godot 4.5, the Mobile renderer, OpenXR, and passthrough/scene settings. The bundled XR Tools has desktop movement and pointer components, but no simulator or Meta Toolkit was found by filename search. Ordinary desktop movement is useful for navigating and checking UI, but does not itself exercise two independent XR hand inputs.

`addons/godot-xr-tools/functions/function_pickup.gd` requires an active controller and reads its grip float. A realistic programmatic grab check therefore needs a valid tracker pose and grip input, followed by physics frames; simply calling the application's grab callback proves less.

Suggested regression paths:

1. Spawn every supported block type with each hand; verify voxel type after placement, undo/redo, and round-trip loading.
2. Spawn with left, grab with right before grid placement, recolor/release; repeat right-to-left. Check real ownership state and signal effects.
3. Save several adjacent multi-cell blocks within the same metre, reload, and assert each occupied cell points to its own master. Remove one block and check the others remain intact. Repeat with negative coordinates and rotated blocks.
4. Render the above scene and capture screenshots at fixed checkpoints; visually inspect block shapes, colors, and surviving geometry.
5. Run the same basic flow in Meta XR Simulator to check actual OpenXR action bindings, pointer hit-testing, and menu/save-load presentation.

The XR Tools pointer documentation explicitly supports running its 2D UI scene directly and interacting with mouse. That makes UI layout and button logic inexpensive to inspect before checking pointer behavior in XR. [XR Tools pointer docs](https://godotvr.github.io/godot-xr-tools/docs/pointer/)
