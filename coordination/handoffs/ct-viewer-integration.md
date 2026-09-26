# CT viewer integration handoff

- Task/state: complete; user explicitly requested merging bitrig/fold-ct-viewer into machmoon/Generalizable main.
- Result: FoldScanView is the Bitrig app entry point. CT depth is controlled by dragging the locator line or by iPhone Duo hinge input.
- Merge resolution: retained GitHub main ContentView, Core, UI, Render, Duo, Cases, web/backend, and ios/Lumen sources. Excluded the superseded AI, Engine, Experience, Import, Models, and Views prototype folders from the app target to prevent duplicate type declarations. No source folders were deleted.
- Files resolved: App/App.swift, App/ContentView.swift, Project.json.
- Checks: combined iOS 27.1 SDK Swift type check passed; Bitrig build log reports BUILD SUCCEEDED; running simulator shows Anatomy, real CT layers, and draggable locator; CTScanChecks passed for three planes, voxel scaling/orientation, invalid inputs, hinge endpoints, touch override, and closed-device continuity.
- Tool note: build_project returned CancellationError after compilation, but the build log and live simulator independently confirmed success.
- Current interaction: 180 degrees selects the first layer, 90 degrees the last; dragging the line pauses follow-fold. This is the approved native restart behavior, distinct from the retained legacy Scan mode.
- No outstanding integration blockers.
