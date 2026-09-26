# RevenueCat integration: Generalizable Pro

> **Demo only.** Public research data. Not a diagnosis. Nothing here sells medical advice. Pro unlocks viewer features only.

This guide adds RevenueCat subscriptions to the Duo app so the project can enter the **Best RevenueCat creation** track. Integration takes about 30 minutes:

1. Add the SDK.
2. Configure it at launch.
3. Check one entitlement.
4. Show a paywall on the Duo's **lower screen** while the scan stays visible on the lid.

## 1. What Pro unlocks

The free tier stays fully demoable. Pro adds features a clinician, educator or presenter would pay for:

| Free | **Pro** (entitlement `pro`) |
|---|---|
| Bundled demo cases (Torso CT, Head CT, The Sun) | **Open your own CT scans** (the NIfTI import button in `FoldScanView`) |
| Fold-to-scrub and fold-to-tilt on the hinge | **Tabletop presenter mode**: the lid faces the patient and the base holds the controls, for bedside explanations |
| Soft-tissue window | **All window presets** (lung, bone) and the layer peel |
| — | **Export** annotated slices and a plain-language explanation card |

**Why this is Duo-native:** the paywall appears on the **base** half in tabletop pose, and the lid keeps showing the scan. You see what you're buying while you decide. On a regular iPhone it falls back to a standard sheet.

## 2. Dashboard setup (RevenueCat)

1. Create a project, then add an **Apple App Store** app with the bundle ID from `Project.json`: `app.bitrig.new.8dc46b5e-4822-4579-8164-5376ed092a21`, or your own.
2. **Products:** add `gz_pro_monthly` ($4.99) and `gz_pro_yearly` ($29.99). For the hackathon, use RevenueCat's **Test Store** or a StoreKit configuration file, so no App Store Connect review is needed.
3. **Entitlement:** create `pro` and attach both products.
4. **Offering:** set `default` as current, with packages `$rc_monthly` and `$rc_annual`.
5. **Paywall:** in *Paywalls*, attach a template to the `default` offering. `RevenueCatUI` renders it, so no custom UI is needed.
6. Copy the **public Apple API key** (`appl_…`). It's safe to ship in the app. Never ship the secret key.

## 3. Add the SDK

**Bitrig / XcodeGen (`Project.json`):** add a top-level `packages` entry and target dependencies:

```json
"packages": {
  "RevenueCat": { "url": "https://github.com/RevenueCat/purchases-ios-spm", "from": "5.0.0" }
},
"targets": {
  "Generalizable": {
    "dependencies": [
      { "package": "RevenueCat", "product": "RevenueCat" },
      { "package": "RevenueCat", "product": "RevenueCatUI" }
    ]
  }
}
```

**Xcode:** File → Add Package Dependencies → `https://github.com/RevenueCat/purchases-ios-spm`, then add **RevenueCat** and **RevenueCatUI** to the app target.

## 4. Configure at launch (`App/App.swift`)

```swift
import SwiftUI
import RevenueCat

@main
struct AppDefinition: App {
  @State private var store = ProStore()

  init() {
    Purchases.logLevel = .warn
    Purchases.configure(withAPIKey: "appl_YOUR_PUBLIC_KEY")
  }

  var body: some Scene {
    WindowGroup {
      FoldScanView()
        .environment(store)
        .task { await store.refresh() }
    }
  }
}
```

## 5. One source of truth for Pro (`App/Store/ProStore.swift`, new)

```swift
import Foundation
import Observation
import RevenueCat

@MainActor @Observable
final class ProStore {
  private(set) var isPro = false
  var showsPaywall = false

  func refresh() async {
    guard let info = try? await Purchases.shared.customerInfo() else { return }
    isPro = info.entitlements["pro"]?.isActive == true
  }

  /// Call before any Pro feature. Returns true if the user can proceed now.
  func require() -> Bool {
    if isPro { return true }
    showsPaywall = true
    return false
  }

  func restore() async {
    if let info = try? await Purchases.shared.restorePurchases() {
      isPro = info.entitlements["pro"]?.isActive == true
    }
  }
}
```

Keep `isPro` current by listening for updates. For example, in `refresh()` or a `.task`:

```swift
for await info in Purchases.shared.customerInfoStream {
  isPro = info.entitlements["pro"]?.isActive == true
}
```

## 6. Gate the features (`App/Scan/FoldScanView.swift`)

```swift
@Environment(ProStore.self) private var store

// Open CT scan (toolbar)
Button("Open CT scan", systemImage: "folder") {
  if store.require() { showsImport = true }
}

// Window presets in FoldScanInspector: lung and bone are Pro
if window != .tissue && !store.require() { return }
```

Add a small lock badge (`Image(systemName: "lock.fill")`) next to Pro-only controls when `!store.isPro`, so the upsell is visible before the tap.

## 7. The Duo paywall: lower screen, scan stays on the lid

Use `RevenueCatUI.PaywallView`, which renders the dashboard template. In **tabletop pose**, place it in the base half of the existing split instead of presenting a sheet:

```swift
import RevenueCatUI

// Inside the regular-width / Duo branch of `workspace`:
ArrangementView {
  mainPane                                  // lid: the scan keeps rendering
} secondary: {
  if store.showsPaywall && !store.isPro {
    PaywallView(displayCloseButton: true)
      .onPurchaseCompleted { info in
        store.showsPaywall = false
        Task { await store.refresh() }
      }
      .onRestoreCompleted { _ in Task { await store.refresh() } }
  } else {
    VStack(spacing: 0) { studyHeader; locatorCanvas }   // existing base content
  }
}
```

On a regular iPhone (compact width), use a sheet:

```swift
.sheet(isPresented: Binding(get: { store.showsPaywall && !store.isPro },
                            set: { store.showsPaywall = $0 })) {
  PaywallView(displayCloseButton: true)
}
```

Optional: RevenueCatUI's `.presentPaywallIfNeeded(requiredEntitlementIdentifier: "pro")` works for a quick, one-line gate on any view.

## 8. Testing

1. Use the RevenueCat **Test Store** API key, or add a **StoreKit Configuration** file to the scheme (Product → Scheme → Edit Scheme → Options), with products matching the dashboard.
2. Run on the iPhone Duo simulator (Xcode 27.1).
3. Tap **Open CT scan**. The paywall should appear on the lower half, with the scan still on the lid.
4. Buy **monthly**. The paywall should close, the import sheet should open, and the Customer should show `pro` active in RevenueCat → Customers.
5. Kill and relaunch the app. `isPro` should stay true (from `customerInfo`), and **Restore** should work.

## 9. Checklist for the Devpost "RevenueCat" track

- [ ] SDK configured with the public key at launch
- [ ] Entitlement `pro` gates import, extra windows, presenter mode and export
- [ ] Duo tabletop paywall on the base screen with the scan visible on the lid
- [ ] Restore purchases available (in the paywall and in settings)
- [ ] Screenshot of the paywall on the Duo for the submission
- [ ] Opt in to **Best RevenueCat creation** on Devpost

**Links:** the [RevenueCat iOS SDK](https://github.com/RevenueCat/purchases-ios) and the [Paywalls docs](https://www.revenuecat.com/docs/tools/paywalls).
