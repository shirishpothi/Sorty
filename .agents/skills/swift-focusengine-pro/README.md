<p align="center">
  <img src="assets/logo.svg" height="180" alt="Swift FocusEngine Pro" />
</p>

<h3 align="center">Agent skill for focus management across all Apple platforms</h3>

<p align="center">
  <img src="https://img.shields.io/badge/tvOS-15+-000000?logo=apple" />
  <img src="https://img.shields.io/badge/iOS-15+-000000?logo=apple" />
  <img src="https://img.shields.io/badge/watchOS-8+-000000?logo=apple" />
  <img src="https://img.shields.io/badge/visionOS-1+-000000?logo=apple" />
  <img src="https://img.shields.io/badge/macOS-12+-000000?logo=apple" />
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-blue" />
  <img src="https://img.shields.io/badge/version-1.6.0-brightgreen" />
</p>

<p align="center">
  <a href="https://skills.sh/mhaviv/Swift-FocusEngine-Agent-Skill">
    <img src="https://img.shields.io/badge/skills.sh-Listed-6C47FF?logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHRleHQgeD0iNCIgeT0iMTgiIGZvbnQtc2l6ZT0iMTYiIGZpbGw9IndoaXRlIj7wn5ugPC90ZXh0Pjwvc3ZnPg==&logoColor=white" />
  </a>
  <a href="https://github.com/twostraws/Swift-Agent-Skills">
    <img src="https://img.shields.io/badge/Swift_Agent_Skills-Listed-F05138?logo=swift&logoColor=white" />
  </a>
  <a href="https://www.awesomeskills.dev/en/skill/mhaviv-swift-focusengine-agent-skill">
    <img src="https://img.shields.io/badge/awesomeskills.dev-Listed-10B981" />
  </a>
  <a href="https://github.com/mhaviv/Swift-FocusEngine-Agent-Skill/stargazers">
    <img src="https://img.shields.io/github/stars/mhaviv/Swift-FocusEngine-Agent-Skill?style=flat&logo=github&label=Stars" />
  </a>
</p>

<p align="center">
  <a href="https://x.com/michael_haviv">
    <img src="https://img.shields.io/badge/Contact-@michael__haviv-1DA1F2?logo=x&logoColor=white" />
  </a>
  <a href="https://www.linkedin.com/in/michaelhaviv/">
    <img src="https://img.shields.io/badge/LinkedIn-Michael_Haviv-0A66C2?logo=linkedin&logoColor=white" />
  </a>
</p>

---

Swift FocusEngine Pro is a free, open-source agent skill that helps AI coding assistants write correct focus management code for **tvOS**, **iOS/iPadOS**, **watchOS**, **visionOS**, and **macOS**. It covers SwiftUI, UIKit, AppKit, and RealityKit — targeting the mistakes LLMs actually make with Apple's focus engine.

Built from real-world experience shipping production tvOS apps, Apple developer documentation, WWDC sessions (2017-2025), and community best practices from Airbnb, Showmax, and others.

Works with [Claude Code](https://claude.ai/code), [Codex](https://openai.com/codex), [Cursor](https://cursor.sh), [GitHub Copilot](https://github.com/features/copilot), [Gemini CLI](https://github.com/google-gemini/gemini-cli), and any tool supporting the [Agent Skills](https://agentskills.io) format.

## Table of Contents

- [Who This Is For](#who-this-is-for)
- [Why Use an Agent Skill for Focus?](#why-use-an-agent-skill-for-focus)
- [Installing](#installing)
- [Using](#using)
- [What It Covers](#what-it-covers)
- [Anti-Patterns It Catches](#anti-patterns-it-catches)
- [FAQ](#faq)
- [Sources](#sources)
- [Complementary Skills](#complementary-skills)
- [Changelog](#changelog)
- [Contributing](#contributing)
- [License](#license)

## Who This Is For

- **tvOS developers** — building apps where every interaction depends on the focus engine working correctly
- **iOS/iPadOS developers** — adding keyboard, game controller, or external display support with focus groups
- **visionOS developers** — navigating the differences between gaze, hover, and focus in spatial computing
- **macOS developers** — building keyboard-navigable apps with key view loops, focus rings, and menu commands

## Why Use an Agent Skill for Focus?

Focus management on Apple platforms is one of the hardest things to get right — and one of the hardest things to debug when it breaks.

The focus engine is geometric, not hierarchical. It doesn't follow your view tree. When a user swipes right and focus jumps two rows away instead of to the next item, there's no error, no crash, no log — it just looks broken. The item wasn't perfectly vertically aligned, so the engine picked a different candidate. You'll spend hours in `UIFocusDebugger` before you figure out why.

Apple's documentation covers the APIs but not the real-world edge cases: what happens when you reload data and focus resets to the top, why `.disabled()` silently removes views from the focus chain on tvOS, why `.focusSection()` is the difference between a usable scroll view and chaos, or why `onHover` doesn't fire from eye gaze on visionOS.

LLMs generate focus code that compiles and looks reasonable — but breaks in ways you only discover on a real device with a Siri Remote in your hand. This skill is built from my experience getting focus to actually work in a complex, production tvOS app. Every anti-pattern in here is something I hit, debugged, and fixed.

## Installing

### Claude Code

```bash
# Global (all projects)
npx skills add https://github.com/mhaviv/Swift-FocusEngine-Agent-Skill --skill swift-focusengine-pro -g -y

# Project-level only
npx skills add https://github.com/mhaviv/Swift-FocusEngine-Agent-Skill --skill swift-focusengine-pro -y
```

### Codex

```bash
npx skills add https://github.com/mhaviv/Swift-FocusEngine-Agent-Skill --skill swift-focusengine-pro --agent codex
```

### Cursor

```bash
npx skills add https://github.com/mhaviv/Swift-FocusEngine-Agent-Skill --skill swift-focusengine-pro --agent cursor
```

### GitHub Copilot

```bash
npx skills add https://github.com/mhaviv/Swift-FocusEngine-Agent-Skill --skill swift-focusengine-pro --agent github-copilot
```

### Gemini CLI

```bash
npx skills add https://github.com/mhaviv/Swift-FocusEngine-Agent-Skill --skill swift-focusengine-pro --agent gemini
```

### Other Agents

Any agent that supports the [Agent Skills](https://agentskills.io) format can use this skill. See [agentskills.io](https://agentskills.io) for instructions on adding skills to your agent.

<details>
<summary>Don't have Node installed?</summary>

```bash
brew install node
```

Or download from [nodejs.org](https://nodejs.org).
</details>

### Updating

Skills are installed as local copies — they don't auto-update. To pull the latest version:

```bash
# Update all installed skills
npx skills update -g -y

# Or reinstall this skill specifically
npx skills add https://github.com/mhaviv/Swift-FocusEngine-Agent-Skill --skill swift-focusengine-pro -g -y
```

⭐ **Star and Watch** this repo to get notified of new releases.

## Using

### Claude Code
```
/swift-focusengine-pro Review this view for tvOS focus issues
```

### Codex
```
$swift-focusengine-pro Check my SwiftUI code for focus anti-patterns
```

### Cursor
```
/swift-focusengine-pro Review this view for tvOS focus issues
```

### GitHub Copilot
```
/swift-focusengine-pro Review this view for tvOS focus issues
```

### Gemini CLI
```
Use the swift-focusengine-pro skill to review my focus handling code
```

### Any Agent
> Use the Swift FocusEngine Pro skill to audit my project for focus management problems

### Example Prompts

- *"Why isn't the first item focused when my view appears?"*
- *"Focus is jumping to a completely different row when I swipe right — the items aren't perfectly aligned vertically"*
- *"How do I keep focus position after my data reloads?"*
- *"I added .disabled() to a button but now focus skips over the entire section"*
- *"What's the difference between gaze and focus on visionOS?"*
- *"My Digital Crown rotation stopped working after I reordered my view modifiers"*
- *"How do I make menu bar commands respond to whichever document window is focused?"*

## What It Covers

### 4,500+ lines of focus expertise across 14 reference files (v1.6)

| Reference | Platform | Coverage |
|-----------|----------|----------|
| **anti-patterns.md** | All | 30 critical mistakes: 17 original tvOS + 6 production tvOS + 7 macOS-specific |
| **swiftui-focus.md** | tvOS | @FocusState, focusSection, prefersDefaultFocus, AutoFocusManager pattern |
| **uikit-focus.md** | tvOS | UIFocusEnvironment, UIFocusGuide, shouldUpdateFocus, didUpdateFocus |
| **ios-focus.md** | iOS/iPadOS | SwiftUI + UIKit: focus groups, focusGroupIdentifier, UIFocusHaloEffect, keyboard nav, focusedValue, game controller, Stage Manager |
| **watchos-focus.md** | watchOS | SwiftUI: Digital Crown routing, sequential focus, Crown conflicts, .digitalCrownAccessory |
| **visionos-focus.md** | visionOS | SwiftUI + UIKit + RealityKit: gaze vs hover vs focus, HoverEffect, HoverEffectComponent |
| **focus-styling.md** | All | ButtonStyle + isFocused, FocusBorder, CABasicAnimation, CardButtonStyle, macOS focus ring styling |
| **focus-restoration.md** | All | Data reload handling, safe reload pattern, row offset tracking |
| **layout-patterns.md** | tvOS | Table-of-collections, sidebar+content, tab bar, hero+catalog |
| **macos-focus.md** | macOS | AppKit + SwiftUI: key view loop, focus ring, NSView focus APIs, focusedValue for menus, Mac Catalyst, Full Keyboard Access |
| **realitykit-focus.md** | visionOS | RealityKit entity hover, collision shapes, gestures, shader effects, mixed hierarchies |
| **async-focus.md** | All | @MainActor coordination, focus after data load, NavigationStack pop, Task cancellation |
| **accessibility-focus.md** | All | @AccessibilityFocusState, VoiceOver + focus, Full Keyboard Access, Switch Control, Reduce Motion |
| **debugging.md** | All | UIFocusDebugger, _whyIsThisViewNotFocusable, launch arguments, macOS first responder debugging |

## Anti-Patterns It Catches

### Blocking (must fix before ship)

1. **`.disabled()` removes views from the focus chain on tvOS** — gate the action inside the closure instead (`.allowsHitTesting(false)` is unreliable)
2. **Missing `.focusSection()` on horizontal ScrollViews** — causes cross-row focus jumping in vertical layouts
3. **Adding `.focusable()` to Buttons or NavigationLinks** — creates double-focus artifacts
4. **Mixing SwiftUI and UIKit focus in the same hierarchy** — focus environment conflicts
5. **Calling `reloadData()` during animations** — focus resets to the top of the screen
6. **Using `frame.width` in focus transform calculations** — dimensions change when focused
7. **`setNeedsFocusUpdate()` called from wrong environment** — silently fails with no error
8. **Setting `isUserInteractionEnabled = false` on headers/labels** — removes them and their children from focus chain
9. **`remembersLastFocusedIndexPath` + offscreen `reloadData()`** — remembered index may no longer exist
10. **Using `UIView.animate` for CALayer properties** — animations won't work, use `CABasicAnimation`

### Warning (should fix)

11. **Non-optional `@FocusState` with `focused(_:equals:)`** — can't represent "nothing focused" state
12. **Missing `prepareForReuse()` cleanup for focus state** — stale focus styling on reused cells
13. **`prefersDefaultFocus` inside ScrollView** — may not work as expected, use `defaultFocus` instead
14. **LazyVStack/LazyVGrid performance on Apple TV HD** — A8 chip can't handle lazy layout recalculation during fast scrolling

### tvOS production patterns

15. **`LazyVStack` deallocates offscreen rows** — rapid upward swipe causes focus to jump to tab bar, skipping content
16. **Missing `.focusSection()` on vertical ScrollView** — focus escapes upward to tab bar/nav bar
17. **Allocating objects in `didUpdateFocus`/`shouldUpdateFocus`** — per-frame garbage causes micro-stutters

### macOS-specific

18. **Not overriding `acceptsFirstResponder` on custom NSView** — view is invisible to Tab navigation
19. **Incomplete key view loop** — Tab stops working after reaching the last view
20. **Calling `becomeFirstResponder()` directly** — bypasses resign/become handshake, use `window.makeFirstResponder`
21. **NSPanel stealing focus** — inspector panels take focus from document window, use `becomesKeyOnlyIfNeeded`
22. **Not restoring focus after sheet/alert** — focus lost to window instead of returning to original view
23. **`.focusable()` on NSViewRepresentable** — creates double focus layer conflicting with AppKit
24. **Menu items not checking for nil focusedValue** — crashes when no window is key

## FAQ

<details>
<summary><strong>How do I set initial focus on a specific view in tvOS?</strong></summary>

In SwiftUI, use `defaultFocus(_:_:)` or `prefersDefaultFocus`. In UIKit, override `preferredFocusEnvironments` on the parent view controller. See [swiftui-focus.md](swift-focusengine-pro/references/swiftui-focus.md) and [uikit-focus.md](swift-focusengine-pro/references/uikit-focus.md).
</details>

<details>
<summary><strong>Focus resets after reloadData — how do I keep focus position?</strong></summary>

Use `remembersLastFocusedIndexPath` or the safe reload pattern that locks focus before reloading. See [focus-restoration.md](swift-focusengine-pro/references/focus-restoration.md).
</details>

<details>
<summary><strong>Focus jumps to the wrong row when I swipe right</strong></summary>

The focus engine is geometric, not hierarchical. Add `.focusSection()` to horizontal ScrollViews to keep focus within rows. See [anti-patterns.md](swift-focusengine-pro/references/anti-patterns.md) (pattern #2).
</details>

<details>
<summary><strong>How do I programmatically move focus?</strong></summary>

You cannot directly set focus. Override `preferredFocusEnvironments` to return the target, then call `setNeedsFocusUpdate()` + `updateFocusIfNeeded()` on the correct focus environment. See [uikit-focus.md](swift-focusengine-pro/references/uikit-focus.md).
</details>

<details>
<summary><strong>UIFocusGuide not working</strong></summary>

Common causes: guide not added to the view hierarchy, `preferredFocusEnvironments` not set on the guide, or incorrect sizing/positioning. Focus guides bridge empty space between focusable views. See [uikit-focus.md](swift-focusengine-pro/references/uikit-focus.md).
</details>

<details>
<summary><strong>What does focusSection() actually do?</strong></summary>

It creates a focus group that the engine treats as a contiguous region, preventing focus from skipping over the section to items in other rows. Essential for horizontal ScrollViews in vertical layouts. See [swiftui-focus.md](swift-focusengine-pro/references/swiftui-focus.md).
</details>

<details>
<summary><strong>How do I debug focus issues on tvOS?</strong></summary>

Use `UIFocusDebugger.checkFocusability(for:)` in the debugger, `_whyIsThisViewNotFocusable` on any UIView, and the `UIFocusLoggingEnabled` launch argument. See [debugging.md](swift-focusengine-pro/references/debugging.md).
</details>

<details>
<summary><strong>Why does .disabled() break focus on Apple TV?</strong></summary>

On tvOS, `.disabled()` removes the view entirely from the focus chain. `.allowsHitTesting(false)` is commonly recommended but is unreliable — it may map to `isUserInteractionEnabled = false` under the hood. The most reliable approach is to gate the action inside the button closure instead of disabling the view. For lists/sidebars, use the dual `@FocusState` + `.disabled()` gating pattern (anti-pattern #25). See [anti-patterns.md](swift-focusengine-pro/references/anti-patterns.md) (patterns #1 and #25).
</details>

<details>
<summary><strong>@FocusState not dismissing keyboard on iOS</strong></summary>

Setting `@FocusState` to `nil` should dismiss the keyboard, but it can fail inside sheets or NavigationStack. See [ios-focus.md](swift-focusengine-pro/references/ios-focus.md) for workarounds.
</details>

<details>
<summary><strong>How do I move focus between TextFields with the keyboard next button?</strong></summary>

Use `@FocusState` with an enum representing each field, then set the next case in `onSubmit`. See [ios-focus.md](swift-focusengine-pro/references/ios-focus.md).
</details>

<details>
<summary><strong>How does keyboard focus navigation work on iPad?</strong></summary>

iOS 15+ added UIFocusSystem support for hardware keyboards. Opt in with `UIFocusHaloEffect`, `focusGroupIdentifier`, and `focusEffect`. See [ios-focus.md](swift-focusengine-pro/references/ios-focus.md).
</details>

<details>
<summary><strong>How does focus work across multiple windows on iPad with Stage Manager?</strong></summary>

Each window scene has its own focus state. Use `focusedSceneValue` to propagate focus information across scenes. See [ios-focus.md](swift-focusengine-pro/references/ios-focus.md) (Stage Manager section).
</details>

<details>
<summary><strong>How do I use focusedSceneValue for multi-window iPad apps?</strong></summary>

Define a `FocusedValueKey`, set values with `.focusedSceneValue()`, and read them with `@FocusedValue` in your menu bar or toolbar commands. See [ios-focus.md](swift-focusengine-pro/references/ios-focus.md).
</details>

<details>
<summary><strong>Digital Crown rotation stops working after reordering view modifiers</strong></summary>

The `.digitalCrownRotation()` modifier is order-sensitive. It must be applied in the correct position relative to other modifiers. See [watchos-focus.md](swift-focusengine-pro/references/watchos-focus.md).
</details>

<details>
<summary><strong>How do I handle nested scrolling conflicts with Digital Crown?</strong></summary>

When a ScrollView contains a Digital Crown control, the Crown drives both scrolling and the control. Use explicit `@FocusState` to determine which element owns the Crown. See [watchos-focus.md](swift-focusengine-pro/references/watchos-focus.md).
</details>

<details>
<summary><strong>What's the difference between hover and focus on visionOS?</strong></summary>

visionOS uses eye tracking for hover (`.hoverEffect()`) and indirect input for focus. They are separate systems. Gaze creates hover highlights, but tap gestures are needed for activation. See [visionos-focus.md](swift-focusengine-pro/references/visionos-focus.md).
</details>

<details>
<summary><strong>How do I customize hover effects in visionOS?</strong></summary>

Use `HoverEffectComponent` on RealityKit entities with styles: default, spotlight, shader, or highlight. For SwiftUI views, use `.hoverEffect(.highlight)` or `.hoverEffect(.lift)`. See [realitykit-focus.md](swift-focusengine-pro/references/realitykit-focus.md).
</details>

<details>
<summary><strong>How does focus work in Mac Catalyst apps?</strong></summary>

Mac Catalyst inherits iPad's `UIFocusSystem` — `UIFocusHaloEffect` renders as a macOS focus ring, and `focusGroupIdentifier` maps to Tab navigation groups. If your iPad app doesn't support keyboard focus, neither will the Catalyst version. See [macos-focus.md](swift-focusengine-pro/references/macos-focus.md) (Mac Catalyst section).
</details>

<details>
<summary><strong>How do I handle keyboard focus in a macOS SwiftUI app?</strong></summary>

Use `@FocusState` (same as iOS) and `.focusable()` for custom views. macOS focus is always active — no hardware keyboard requirement. For menu bar integration, use `focusedValue` / `focusedSceneValue`. See [macos-focus.md](swift-focusengine-pro/references/macos-focus.md).
</details>

<details>
<summary><strong>Focus works in simulator but not on device (or vice versa)</strong></summary>

The focus engine behaves differently between Xcode Simulator and physical hardware, especially for tvOS remote gestures and visionOS eye tracking. Always test focus on real devices. See [debugging.md](swift-focusengine-pro/references/debugging.md).
</details>

## Sources

Built from:
- Apple Developer Documentation (UIFocusEnvironment, UIFocusGuide, FocusState, focusSection, HoverEffect)
- WWDC17: Focus Interaction in tvOS 11
- WWDC21: Direct and reflect focus in SwiftUI + Focus on iPad keyboard navigation
- WWDC23: The SwiftUI cookbook for focus
- WWDC24: Create custom hover effects in visionOS
- WWDC25: Design hover interactions for visionOS
- Production tvOS apps with complex focus requirements
- Community guides (Airbnb, Showmax, Fatbobman, Big Nerd Ranch)

## Complementary Skills

Swift FocusEngine Pro pairs well with these skills:

- [SwiftUI Pro](https://github.com/twostraws/SwiftUI-Agent-Skill) by Paul Hudson — SwiftUI best practices and patterns
- [Swift Concurrency Pro](https://github.com/twostraws/Swift-Concurrency-Agent-Skill) by Paul Hudson — async/await, actors, Sendable
- [Swift Concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) by Antoine van der Lee — Swift 6 migration, data race prevention
- [Xcode Build Optimization](https://github.com/AvdLee/Xcode-Build-Optimization-Agent-Skill) by Antoine van der Lee — build benchmarking and optimization

See the [Swift Agent Skills](https://github.com/twostraws/Swift-Agent-Skills) directory for more.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

## Contributing

Contributions are welcome! Focus on:

- **Edge cases** — non-obvious focus behaviors that catch developers off guard
- **New platform APIs** — iOS 19, tvOS 19, visionOS 3, watchOS 12, macOS 16 additions
- **Real-world patterns** — battle-tested solutions from production apps
- **Anti-patterns** — mistakes LLMs commonly generate

Keep reference files focused and under 300 lines each. Don't repeat things LLMs already know — focus on what they get wrong. All contributions must be MIT licensed.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) before contributing.

## License

Swift FocusEngine Pro was created by [Michael Haviv](https://github.com/mhaviv) and is licensed under the [MIT License](LICENSE).
