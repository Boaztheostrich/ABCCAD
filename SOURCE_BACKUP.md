# CAD source backup — 2026-10-20

Snapshot of the local 1.4.27-cad-test development source, based on the existing dev branch. Open `1.4.0/project.godot` with Godot 4.5. See `1.4.0/cad/README.md` for sketching, multi-area extrusion, Add/Remove, constraints, depth editing, movable dimensions, undo/redo, save/load, and STL export.

Personal Drive configuration, signing credentials, APKs, Android build output, editor caches, and local test sessions/evidence are excluded. Export settings omit the personal Drive configuration; the optional upload helper uses a placeholder destination folder. Configure credentials locally for personal builds. Existing published APKs remain in repository history; this branch is a source backup and does not publish a new APK.

The original local development checkout is unchanged. This snapshot does not represent new physical headset validation.

Validation on the sanitized copy: feature labels (30), multi-shape sketches (55), and extrusion dragging (32), totaling 117 checks with zero failures. For the multi-shape test, create the ignored `1.4.0/builds/` directory first; it writes an STL fixture there. CAD script/scene/UID files match the live source byte for byte. All 911 tracked files were scanned for known local credential values and common credential patterns, with no matches.
