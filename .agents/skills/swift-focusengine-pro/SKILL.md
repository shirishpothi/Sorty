---
name: swift-focusengine-pro
description: Reviews, writes, and fixes focus management code for all Apple platforms (tvOS, iOS/iPadOS, watchOS, visionOS, macOS), covering SwiftUI, UIKit, AppKit, and RealityKit. Use when reading, writing, or reviewing apps that handle focus, hover, key view loops, or Digital Crown navigation.
license: MIT
metadata:
  author: Michael Haviv
  version: "1.6"
  repository: https://github.com/mhaviv/Swift-FocusEngine-Agent-Skill
  homepage: https://github.com/mhaviv/Swift-FocusEngine-Agent-Skill
  keywords:
    - swift
    - swiftui
    - uikit
    - tvos
    - ios
    - ipados
    - watchos
    - visionos
    - macos
    - focus-engine
    - focus-management
    - apple
    - realitykit
    - accessibility
    - agent-skill
---

Review focus management code for correctness, modern API usage, and adherence to Apple's focus engine rules. Covers all Apple platforms. Report only genuine problems — do not nitpick or invent issues.

Review process:

1. Check for critical anti-patterns using `references/anti-patterns.md`.
2. Determine the target platform and load the appropriate references:
   - **tvOS**: `references/swiftui-focus.md` and `references/uikit-focus.md`.
   - **iOS/iPadOS**: `references/ios-focus.md` (focus groups, halo, keyboard nav).
   - **watchOS**: `references/watchos-focus.md` (Digital Crown, sequential focus).
   - **visionOS**: `references/visionos-focus.md` (gaze, hover effects) and `references/realitykit-focus.md` (RealityKit entities, gestures, volumes).
   - **macOS**: `references/macos-focus.md` (key view loop, focus ring, NSView focus, focusedValue for menus, Mac Catalyst).
   - For cross-platform: load all relevant references.
3. Check focus styling and visual feedback using `references/focus-styling.md`.
4. Verify focus restoration and data reload handling using `references/focus-restoration.md`.
5. Audit layout patterns for focus section isolation using `references/layout-patterns.md`.
6. Check async/await and data loading focus patterns using `references/async-focus.md`.
7. Verify accessibility integration using `references/accessibility-focus.md`.
8. Check debugging and testing practices using `references/debugging.md`.

If doing a partial review, load only the relevant reference files.


## Core Instructions

### tvOS
- tvOS uses a focus-based navigation model — every interactive element must be reachable via the Siri Remote's directional pad.
- Focus movement is purely geometric — the focus engine draws a rectangle from the currently focused view in the swipe direction and picks the nearest focusable view in that rectangle.
- If nothing is in the geometric path, focus does not move. Period. Use `.focusSection()` (SwiftUI) or `UIFocusGuide` (UIKit) to bridge gaps.
- Never use `.disabled()` on tvOS to toggle interactivity — it removes views from the focus chain entirely. `.allowsHitTesting(false)` is **unreliable** on tvOS (may map to `isUserInteractionEnabled = false`). Preferred: gate the action inside the button closure, or use the dual `@FocusState` + `.disabled()` gating pattern for lists (anti-pattern #25).
- `prefersDefaultFocus(_:in:)` does NOT work inside `ScrollView` on tvOS — use `defaultFocus(_:_:priority:)` instead. Note: `defaultFocus` with `.userInitiated` only fires on initial appearance, NOT on every re-entry.
- Prefer `ScrollPosition` over `ScrollViewReader.scrollTo()` — imperative scrollTo creates feedback loops with the focus engine (anti-pattern #26).
- Always test on real Apple TV hardware — Simulator focus behavior differs.

### iOS/iPadOS
- Focus is a secondary interaction model — it only activates with a hardware keyboard connected.
- Tab moves between focus groups; arrow keys move within a group. This two-level model does NOT exist on tvOS.
- Use `focusGroupIdentifier` (iOS 15+, UIKit) to define custom focus groups — this API is NOT available on tvOS.
- Use `UIFocusHaloEffect` to customize the system focus ring — NOT available on tvOS.
- Set `allowsFocus = true` and `selectionFollowsFocus = true` on collection/table views for keyboard navigation.
- Your app must work perfectly without keyboard focus — always test with touch only.

### watchOS
- Focus routes **Digital Crown input** to the correct view — shown by a green border.
- Focus is sequential (layout order), NOT spatial/directional.
- `.focusSection()` is NOT available on watchOS.
- `.focusable()` MUST come BEFORE `.digitalCrownRotation()` — reversing silently breaks crown input.
- Do NOT add `.focusable()` to system controls (Picker, Stepper, Toggle) — they already handle it.

### visionOS
- Eye gaze = hover targeting, NOT focus. `onHover(perform:)` does NOT fire from gaze — only from pointer devices.
- Use `.hoverEffect()` for gaze visual feedback. System controls get it automatically; custom views need it explicitly.
- `@FocusState` only activates with keyboard (Magic Keyboard), VoiceOver, or Switch Control.
- RealityKit entities need `InputTargetComponent` + `CollisionComponent` + `HoverEffectComponent` for gaze interaction.
- `.focusEffectDisabled()` hides keyboard focus ring; `.hoverEffectDisabled()` disables gaze hover — they are different.

### macOS
- macOS uses a key view loop — Tab/Shift-Tab moves between views in a defined sequence. This is NOT spatial like tvOS.
- Custom NSView subclasses must override `acceptsFirstResponder` to return `true` — the default is `false`, making the view invisible to Tab navigation.
- `recalculatesKeyViewLoop = true` on NSWindow overwrites all manual `nextKeyView` connections. Pick one approach.
- Focus ring customization: override `focusRingType`, `focusRingMaskBounds`, and `drawFocusRingMask()` on NSView.
- `focusedValue` / `focusedSceneValue` are critical on macOS for making menu bar commands respond to the current selection.
- Mac Catalyst: inherits iPad `UIFocusSystem`. If the iPad app doesn't support keyboard focus, the Catalyst app won't either.
- Full Keyboard Access is OFF by default — most users only Tab between text fields and lists, not all controls.

### All Platforms
- Never add `.focusable()` to Buttons or NavigationLinks — they are already focusable. Adding it creates a double-focus wrapper.
- Do not mix `@FocusState` (SwiftUI) and UIKit focus APIs (`setNeedsFocusUpdate`) on the same view hierarchy branch.
- VoiceOver focus (`@AccessibilityFocusState`) is completely separate from UI focus (`@FocusState`).


## Output Format

Organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated (e.g., "Use `.allowsHitTesting(false)` instead of `.disabled()`").
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

Example output:

### TopicsView.swift

**Line 49: `.disabled()` removes view from tvOS focus chain (anti-pattern #1).**

```swift
// Before
TopicClipsGridView(...)
    .disabled(!wrapper.isGridFocusable)

// After — gate the action, not the view
TopicClipsGridView(...)
    .opacity(wrapper.isGridFocusable ? 1.0 : 0.5)
// Move the guard inside the button/action closures instead
```

**Line 72: Missing `.focusSection()` on horizontal ScrollView in vertical layout.**

```swift
// Before
ScrollView(.horizontal) {
    HStack { /* row items */ }
}

// After
ScrollView(.horizontal) {
    HStack { /* row items */ }
}
.focusSection()
```

### Summary

1. **Focus breakage (critical):** `.disabled()` on line 49 removes grid from focus chain entirely.
2. **Focus jumping (high):** Missing `.focusSection()` causes cross-row focus jumps.

End of example.


## References

- `references/anti-patterns.md` — Critical mistakes that break focus navigation: 14 tvOS + 7 macOS-specific anti-patterns.
- `references/swiftui-focus.md` — SwiftUI focus APIs: @FocusState, focusSection, prefersDefaultFocus, focused, defaultFocus, onMoveCommand.
- `references/uikit-focus.md` — UIKit focus APIs: UIFocusEnvironment, UIFocusGuide, shouldUpdateFocus, didUpdateFocus, preferredFocusEnvironments, UIFocusDebugger.
- `references/focus-styling.md` — Focus visual feedback: ButtonStyle with isFocused, FocusBorder, hover effects, scale/shadow animations, macOS focus ring styling.
- `references/focus-restoration.md` — Handling focus after data reloads, navigation, and async updates.
- `references/layout-patterns.md` — Common tvOS layouts: table-of-collections, sidebar+content, tab bar, horizontal shelves.
- `references/ios-focus.md` — iOS/iPadOS-specific: focus groups, focusGroupIdentifier, UIFocusHaloEffect, keyboard navigation, allowsFocus, selectionFollowsFocus.
- `references/watchos-focus.md` — watchOS-specific: Digital Crown routing, sequential focus, digitalCrownRotation, focusable ordering.
- `references/visionos-focus.md` — visionOS-specific: gaze vs focus vs hover, HoverEffect, HoverEffectGroup, RealityKit HoverEffectComponent, spatial input.
- `references/macos-focus.md` — macOS-specific: key view loop, NSView focus (acceptsFirstResponder, canBecomeKeyView), focus ring customization, focusedValue for menus, Mac Catalyst, Full Keyboard Access.
- `references/realitykit-focus.md` — RealityKit entity hover: HoverEffectComponent, collision shapes, gestures, shader effects, mixed SwiftUI+RealityKit hierarchies.
- `references/async-focus.md` — Async focus patterns: @MainActor coordination, focus after data load, NavigationStack pop, Task cancellation, debouncing.
- `references/accessibility-focus.md` — Accessibility integration: @AccessibilityFocusState, VoiceOver + focus, Full Keyboard Access, Switch Control, Reduce Motion.
- `references/debugging.md` — UIFocusDebugger, _whyIsThisViewNotFocusable, launch arguments, Quick Look, macOS first responder debugging.
