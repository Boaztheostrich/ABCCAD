# Public release checklist

- [ ] Remind Boaz immediately before the public push: remove the personal Drive
  upload key/config from the public package. He explicitly requested leaving
  the key in personal test builds for now (2026-10-19).
- [ ] Build a fresh public APK without `drive_upload.cfg`; inspect the packaged
  assets and confirm that it contains no personal upload key. Do not distribute
  an existing personally configured test APK.
- [ ] Run the CAD/export regressions and a short physical Quest test: sketch,
  extrude, multi-area cut, undo/redo, save/load, STL export, and slicer import.
- [ ] Verify the STL topology safeguard: selecting both bow-tie lobes as one part
  is rejected; either lobe separately works; an older invalid design loads but
  selected and combined STL exports show a clear error instead of writing a file.

Layers preview and dense-sketch performance remain deferred by user request.
