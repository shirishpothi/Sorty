# Changelog

All notable changes to Swift FocusEngine Pro are documented here.

## [1.6.0] - 2026-04-29

### Added
- **New tvOS anti-pattern #30** — Missing `preferredFocusEnvironments` override on UIKit view controllers with multiple focusable subviews. Without an explicit override, tvOS picks the geometrically first focusable view, which often lands on a secondary CTA (e.g., "Back to Home") instead of the primary action (e.g., "Sign In").
- **Absence-check trigger** — pr-review-style guidance now flags vertical `UIStackView` of buttons, focusable list + standalone buttons, conditional CTA, and modal/sheet presentations that lack a `preferredFocusEnvironments` override. Absence of the override is itself a finding.
- **`uikit-focus.md`: "When to override `preferredFocusEnvironments`" section** — enumerates the trigger conditions and provides a conditional-CTA pattern with `setNeedsFocusUpdate()` cross-reference (anti-pattern #7) for state changes after the view appears.
- Total anti-patterns: 30 (up from 29)

## [1.5.0] - 2026-04-13

### Added
- **5 new production tvOS anti-patterns** (#25–29) from large-scale media-app tvOS development:
  - #25: `.disabled()` on multiple list items with active selection state — mass-toggle focus cascade
  - #26: `ScrollViewReader.scrollTo()` inside `onChange` creates feedback loops with focus engine
  - #27: `@Observable` same-value mutation triggers unnecessary body re-evaluation
  - #28: `defaultFocus` with `.userInitiated` only fires on initial appearance, not re-entry
  - #29: Transient focus bouncing during navigation transitions (sidebar pass-through)
- **Production sidebar pattern** — dual `@FocusState` (container + per-item) with `.disabled()` gating for focus re-entry
- **UIKit reference-codebase sidebar comparison** — `remembersLastFocusedIndexPath`, container-level `isUserInteractionEnabled`, 0.5s debounce
- **`ScrollPosition` vs `ScrollViewReader`** — declarative scroll binding that doesn't fight the focus engine
- **Scroll edge fade patterns** — `.scrollEdgeEffectStyle(.soft)` (tvOS 26+), manual gradient mask with `.mask()`, `onGeometryChange` tracking
- **Focus scale matching** — reference 1.13x scale comparison table for SwiftUI `scaleEffect`
- **`@Observable` focus integration** — same-value guard, `@ObservationIgnored` for non-UI state
- **ScrollTo feedback loop documentation** — detailed cause/fix in `async-focus.md`
- **Focus cascade debugging guide** — structured logging patterns, what to look for in cascade logs
- **VoiceOver scroll animation guard** — check `UIAccessibility.isVoiceOverRunning` before animated scroll
- **Updated anti-pattern #1** — added caveat about `.allowsHitTesting(false)` reliability on tvOS
- **Updated SKILL.md core instructions** — `defaultFocus` re-entry limitation, `ScrollPosition` preference
- Total anti-patterns: 29 (up from 24)

## [1.4.0] - 2026-04-10

### Added
- **3 new tvOS anti-patterns from production** (#15–17) — `LazyVStack` focus escape, vertical `.focusSection()`, allocation in focus callbacks
- **VStack + inner LazyHStack pattern** — lightweight outer container stays in hierarchy, heavy content stays lazy inside each row
- **Tab bar focus escape detection** — `didUpdateFocus` pattern for detecting when focus escapes content to tab bar
- **VoiceOver card composition pattern** — `.accessibilityElement(children: .ignore)` with composed labels for multi-element focusable cards
- Total anti-patterns: 24 (up from 21)

## [1.3.0] - 2026-04-10

### Added
- **macOS focus coverage** — new `macos-focus.md` reference file (650+ lines)
  - AppKit: NSResponder chain, `acceptsFirstResponder`, `canBecomeKeyView`, key view loop
  - Key window vs main window, NSPanel focus behavior, `becomesKeyOnlyIfNeeded`
  - Focus ring: `NSFocusRingType`, `drawFocusRingMask()`, custom shapes
  - SwiftUI on macOS: `@FocusState`, `.focusable()`, `.focusSection()`, `.onKeyPress`
  - `focusedValue` / `focusedSceneValue` for menu bar commands
  - NSToolbar, NSPopover, sheets, NSAlert focus
  - Multi-window, multi-screen, external display
  - Mac Catalyst bridging
  - Full Keyboard Access
- **7 macOS-specific anti-patterns** (#15–21) in `anti-patterns.md`
- macOS focus ring styling in `focus-styling.md`
- macOS VoiceOver, NSAccessibility, Voice Control in `accessibility-focus.md`
- macOS first responder debugging in `debugging.md`
- macOS layout patterns (sidebar, toolbar, multi-window, inspector, three-column) in `layout-patterns.md`
- macOS focus restoration (sheets, NSDocument revert) in `focus-restoration.md`

## [1.2.0] - 2026-04-08

### Added
- **Expanded iOS focus coverage** — game controller focus, Stage Manager multi-window, `.onKeyPress`, pointer hover effects, `focusedValue` / `focusedSceneValue` deep dive
- **Expanded watchOS focus coverage** — `.digitalCrownAccessory()`, nested scrolling conflicts, managing multiple focusable controls
- FAQ section with 20 collapsible questions (tvOS, iOS, iPadOS, watchOS, visionOS, macOS)
- `llms.txt` for AI model discovery
- SKILL.md keyword metadata for registry indexing
- Community health files: CONTRIBUTING.md, issue templates, PR template

## [1.1.0] - 2026-04-07

### Added
- **watchOS focus reference** — Digital Crown routing, sequential focus, `.focusable()` ordering, Crown conflicts
- **RealityKit focus reference** — `HoverEffectComponent`, collision shapes, shader effects, mixed SwiftUI + RealityKit hierarchies
- **Accessibility focus reference** — `@AccessibilityFocusState`, VoiceOver coordination, Full Keyboard Access, Switch Control, Reduce Motion

## [1.0.0] - 2026-04-06

### Added
- Initial release with 10 reference files covering tvOS, iOS/iPadOS, and visionOS
- SwiftUI and UIKit focus management
- 14 critical anti-patterns
- Focus styling, restoration, layout patterns, async coordination, debugging
- Agent Skills format (SKILL.md) for Claude Code, Codex, Cursor, Copilot, Gemini CLI
