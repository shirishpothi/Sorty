# Accessibility and Focus

UI focus (`@FocusState`) and accessibility focus (`@AccessibilityFocusState`) are completely separate systems. Getting both right is essential for tvOS, iOS, visionOS, and macOS apps.

## @FocusState vs @AccessibilityFocusState

| | @FocusState | @AccessibilityFocusState |
|---|---|---|
| **Purpose** | UI navigation (remote, keyboard, controller) | VoiceOver/assistive technology cursor |
| **Trigger** | Siri Remote swipe, Tab key, arrow keys | VoiceOver swipe, Switch Control |
| **Visual** | Focus ring, scale, highlight | VoiceOver cursor (black rectangle) |
| **System** | UIFocusSystem / SwiftUI focus engine | UIAccessibility / SwiftUI accessibility |
| **Coexist** | Yes — both can be active on different elements simultaneously |

### SwiftUI

```swift
struct FormView: View {
    @FocusState private var uiFocus: Field?
    @AccessibilityFocusState private var voFocus: Field?
    
    enum Field { case name, email, submit }
    
    var body: some View {
        VStack {
            TextField("Name", text: $name)
                .focused($uiFocus, equals: .name)
                .accessibilityFocused($voFocus, equals: .name)
            
            TextField("Email", text: $email)
                .focused($uiFocus, equals: .email)
                .accessibilityFocused($voFocus, equals: .email)
            
            Button("Submit") { validate() }
                .focused($uiFocus, equals: .submit)
                .accessibilityFocused($voFocus, equals: .submit)
        }
    }
    
    func showError(on field: Field) {
        uiFocus = field       // Move keyboard/remote focus
        voFocus = field       // Move VoiceOver cursor
    }
}
```

Setting both ensures sighted users and VoiceOver users both land on the error field.

## VoiceOver + Focus Coordination

### tvOS

On tvOS, VoiceOver changes how the Siri Remote works:
- Swipe left/right moves VoiceOver cursor (not UI focus)
- Double-tap activates the VoiceOver-focused element
- UI focus and VoiceOver focus move together by default, but can desync if you programmatically set one without the other

**Rule:** When programmatically moving focus on tvOS, also move accessibility focus if VoiceOver might be active.

### iOS

On iOS, VoiceOver focus is independent of keyboard focus:
- VoiceOver users swipe to navigate sequentially
- Keyboard users Tab/arrow to navigate by focus groups
- Both can be active simultaneously (external keyboard + VoiceOver)

### visionOS

On visionOS, VoiceOver replaces gaze as the targeting mechanism:
- Different hand gestures for navigation (finger pinches)
- Hover effects still render but are not the primary feedback
- Accessibility labels on RealityKit entities are critical

```swift
entity.accessibilityLabel = "3D Trophy Model"
entity.isAccessibilityElement = true
```

## Full Keyboard Access (iOS/iPadOS)

Full Keyboard Access (Settings > Accessibility > Keyboards) enables Tab/arrow navigation for ALL users, not just those with hardware keyboards connected. It activates the full focus system.

### Focus Groups with Full Keyboard Access

```swift
VStack {
    // Group 1: Navigation
    HStack {
        Button("Home") { }
        Button("Search") { }
        Button("Settings") { }
    }
    .focusSection()
    
    // Group 2: Content
    LazyVGrid(columns: columns) {
        ForEach(items) { item in
            CardView(item: item)
        }
    }
    .focusSection()
}
```

Tab moves between groups. Arrow keys move within a group. Without `.focusSection()`, Tab moves through every individual element.

### UIFocusGroupPriority (UIKit)

Controls which focus group receives initial focus when multiple groups exist:

```swift
// Higher priority = gets focus first
navigationBar.focusGroupPriority = .prioritized  // .prioritized > .default > .ignored
contentArea.focusGroupPriority = .default
```

## Switch Control

Switch Control lets users navigate with external switches (buttons, head movements, eye tracking on supported devices).

### tvOS
- Auto Scanning mode cycles through focusable elements
- Elements must be in the focus chain to be reachable
- `.disabled()` anti-pattern also breaks Switch Control navigation

### iOS
- Point Scanning and Item Scanning modes
- Respects accessibility element grouping
- `.accessibilityElement(children: .combine)` groups children into one switch target

### visionOS
- Uses Dwell Control variant — gaze at element for set duration
- RealityKit entities need accessibility properties

## Accessibility Labels for Focusable Elements

Focusable elements without accessibility labels are announced as their type only ("Button", "Link"), which is useless to VoiceOver users.

```swift
// BAD
Button(action: play) {
    Image(systemName: "play.fill")
}

// GOOD
Button(action: play) {
    Image(systemName: "play.fill")
}
.accessibilityLabel("Play video")
```

### TVos Focused State Announcements

When focus moves to a new element on tvOS, VoiceOver announces the element. Custom views must provide meaningful labels:

```swift
CardView(show: show)
    .focusable()
    .accessibilityLabel("\(show.title), \(show.genre)")
    .accessibilityHint("Press select to play")
    .accessibilityAddTraits(.isButton)
```

### Composing VoiceOver Labels on Focusable Cards

Cards with multiple text elements (eyebrow, title, duration, live badge) are focusable as a single unit on tvOS. Without a composed label, VoiceOver reads each subview individually — confusing and slow.

```swift
// BAD — VoiceOver reads "News", "Breaking Story Title", "LIVE", "2:34" separately
CardView(clip: clip)
    .focusable()

// GOOD — single composed announcement
CardView(clip: clip)
    .focusable()
    .accessibilityElement(children: .ignore)  // Hide subviews from VoiceOver
    .accessibilityLabel(composeLabel(for: clip))
    .accessibilityAddTraits(clip.isLive ? [.isButton, .updatesFrequently] : .isButton)
    .accessibilityHint("Press select to play")

func composeLabel(for clip: Clip) -> String {
    var parts = [clip.eyebrow, clip.title]
    if clip.isLive { parts.append("Live") }
    if let duration = clip.formattedDuration { parts.append(duration) }
    if clip.isLocked { parts.append("Locked") }
    return parts.compactMap { $0 }.joined(separator: ", ")
}
```

This pattern is critical for media apps where cards contain 3-5 text elements plus status badges.

## Custom Actions and Focus

VoiceOver custom actions let users perform secondary actions without navigating away from the focused element.

```swift
CardView(show: show)
    .accessibilityAction(named: "Add to favorites") {
        addToFavorites(show)
    }
    .accessibilityAction(named: "More info") {
        showDetails(show)
    }
```

On tvOS, these appear in the VoiceOver rotor. On iOS, swipe up/down to cycle through actions.

## Focus Order and Accessibility Order

SwiftUI accessibility order follows the view hierarchy by default. Focus order (for keyboard/remote) is geometric. These can conflict.

### When They Conflict

```swift
// Visual layout: [B] [A] [C] (A is visually centered but declared second)
HStack {
    ButtonB()  // VoiceOver reads first, focus engine may focus first
    ButtonA()  // VoiceOver reads second
    ButtonC()  // VoiceOver reads third
}
```

To override accessibility reading order without changing focus geometry:

```swift
HStack {
    ButtonB()
        .accessibilitySortPriority(1)
    ButtonA()
        .accessibilitySortPriority(3)  // Read first by VoiceOver
    ButtonC()
        .accessibilitySortPriority(2)
}
```

`accessibilitySortPriority` does NOT affect keyboard/remote focus order.

## Dynamic Type and Focus

Large text sizes can change view dimensions, which affects the focus engine's geometric calculations on tvOS.

- Larger text = larger focus targets (good)
- But can push elements off-screen or misalign them vertically (bad for focus geometry)
- Always test focus navigation with the largest Dynamic Type size

## Reduce Motion and Focus Animations

When Reduce Motion is enabled (Settings > Accessibility > Motion), focus animations should be simplified:

```swift
struct CardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.isFocused) var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isFocused)
    }
}
```

In UIKit:

```swift
override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    if UIAccessibility.isReduceMotionEnabled {
        // Apply state change immediately, no animation
        self.transform = isFocused ? CGAffineTransform(scaleX: 1.05, y: 1.05) : .identity
    } else {
        coordinator.addCoordinatedFocusingAnimations({ _ in
            self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }, completion: nil)
    }
}
```

## VoiceOver Guard on Animated Scroll (tvOS)

When using `withAnimation` for programmatic scrolling in sidebars or lists, VoiceOver users can get disoriented by unexpected scroll animations. Check `UIAccessibility.isVoiceOverRunning` and skip animation:

```swift
.onChange(of: focusedIndex) { _, newIndex in
    guard let index = newIndex else { return }
    if UIAccessibility.isVoiceOverRunning {
        scrollPosition.scrollTo(id: index)  // No animation
    } else {
        withAnimation(.easeInOut(duration: 0.2)) {
            scrollPosition.scrollTo(id: index)
        }
    }
}
```

This prevents VoiceOver from losing its place when the viewport moves unexpectedly.

## Common Mistakes

### 1. Setting @FocusState but not @AccessibilityFocusState on error
Sighted users see focus move to the error field. VoiceOver users hear nothing because VoiceOver cursor did not move.

### 2. Using .disabled() which also removes from VoiceOver
`.disabled(true)` makes elements inaccessible to both focus AND VoiceOver. On tvOS, gate the action inside the button closure instead of disabling the view (see anti-pattern #1). Note: `.allowsHitTesting(false)` is unreliable on tvOS and may also remove views from VoiceOver. Always set `.accessibilityLabel` with disabled state info regardless of approach.

### 3. Missing accessibility labels on focusable custom views
VoiceOver announces "Button" with no context. Every focusable element needs a descriptive label.

### 4. Ignoring Reduce Motion for focus animations
Scale and shadow animations on focus change can cause discomfort. Check `accessibilityReduceMotion` or `UIAccessibility.isReduceMotionEnabled`.

### 5. Not testing with VoiceOver on tvOS
VoiceOver on tvOS works very differently from iOS. The Siri Remote interaction model changes completely. Test with actual Apple TV + VoiceOver enabled.

### 6. Accessibility order conflicting with focus order
VoiceOver reads in view tree order, focus engine navigates geometrically. Users can get confused when the two orders diverge significantly.

## macOS Accessibility and Focus

### VoiceOver on macOS

macOS VoiceOver uses `VO+Arrow` keys (Control+Option+Arrow) to navigate, separate from Tab focus:

- **Tab focus**: `@FocusState` / first responder (keyboard navigation)
- **VoiceOver cursor**: Controlled by VO key commands, follows accessibility element order
- Both systems are active simultaneously when VoiceOver is on

```swift
// SwiftUI — same API, works on macOS
@AccessibilityFocusState private var voFocus: Field?

TextField("Name", text: $name)
    .accessibilityFocused($voFocus, equals: .name)
```

### NSAccessibility Protocol (AppKit)

AppKit views conform to `NSAccessibilityProtocol`. Focus-related properties:

```swift
class MyView: NSView {
    override func accessibilityFocusedUIElement() -> Any? {
        // Return the sub-element that VoiceOver should focus
        return self
    }

    override var isAccessibilityFocused: Bool {
        // Whether VoiceOver cursor is on this element
        return window?.firstResponder === self
    }

    override func accessibilityPerformPress() -> Bool {
        // Called when VoiceOver activates this element (VO+Space)
        performAction()
        return true
    }
}
```

### Full Keyboard Access on macOS

macOS Full Keyboard Access (System Settings > Keyboard > Keyboard Navigation) affects:
- ALL controls become Tab-focusable (buttons, checkboxes, sliders, pop-ups)
- Focus ring appears on all focused controls
- Same focus system as regular Tab navigation — `canBecomeKeyView` determines reachability

```swift
// Check at runtime
if NSApplication.shared.isFullKeyboardAccessEnabled {
    // FKA is on — all controls get focus
} else {
    // Only text fields and lists receive Tab focus by default
}
```

### Voice Control on macOS

Voice Control (macOS 10.15+) shows numbered labels on all interactive elements. Focusable elements that lack accessibility labels get generic numbers only, making them hard to target by voice.

```swift
// BAD — Voice Control shows "Button 7" with no context
Button(action: save) {
    Image(systemName: "square.and.arrow.down")
}

// GOOD — Voice Control shows "Save" label
Button(action: save) {
    Image(systemName: "square.and.arrow.down")
}
.accessibilityLabel("Save")
```

### macOS Accessibility Focus Mistakes

**7. Not setting accessibility labels on toolbar items.** NSToolbarItem buttons are often icon-only. VoiceOver announces "Button" with no context.

**8. Menu items without proper accessibility.** Custom menu items should have accessibility labels if they contain non-text content (icons, custom views).

**9. Ignoring VoiceOver with NSPanel.** Floating panels and popovers can confuse VoiceOver's navigation order. Set `accessibilityModal = true` on modal panels so VoiceOver doesn't read behind them.
