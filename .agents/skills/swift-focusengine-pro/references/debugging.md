# Debugging Focus Issues (tvOS + macOS)

## UIFocusDebugger (LLDB Commands)

Available tvOS 11+. Use in Xcode debugger during a breakpoint.

### Check current focus status
```
(lldb) po UIFocusDebugger.status()
```
Shows the currently focused item and its focus environment chain.

### Check why a view can't receive focus
```
(lldb) po UIFocusDebugger.checkFocusability(for: myView)
```
Returns detailed explanation of why the view is or isn't focusable. Checks:
- `canBecomeFocused` return value
- `isHidden`
- `alpha == 0`
- `isUserInteractionEnabled`
- Whether the view is in a window
- Whether an ancestor blocks focus

### Simulate a focus update
```
(lldb) po UIFocusDebugger.simulateFocusUpdateRequest(from: myEnvironment)
```
Walks the preferred focus chain without actually moving focus. Shows which view WOULD receive focus.

### Check focus group tree
```
(lldb) po UIFocusDebugger.checkFocusGroupTree(for: focusSystem)
```
Prints the entire focus group hierarchy.

### List all commands
```
(lldb) po UIFocusDebugger.help()
```

## _whyIsThisViewNotFocusable (Hidden Debug Method)

Not in public API but invaluable for debugging:

```
(lldb) po [myView _whyIsThisViewNotFocusable]
```

Returns human-readable list of issues:
- "userInteractionEnabled set to NO"
- "canBecomeFocused returns NO"
- "view is hidden"
- "alpha is 0"
- "view is obscured by another view"
- "ancestor has userInteractionEnabled = NO"
- "not in a window"

## Launch Arguments

### -UIFocusLoggingEnabled YES

Add to scheme's launch arguments. Logs every focus update to the console with:
- The preferred focus environment search chain
- Which view was selected and why
- Which views were considered and rejected

### How to add
Xcode -> Product -> Scheme -> Edit Scheme -> Run -> Arguments -> "+" -> `-UIFocusLoggingEnabled YES`

## Quick Look on UIFocusUpdateContext

In `shouldUpdateFocus(in:)` or `didUpdateFocus(in:with:)`:
1. Set breakpoint
2. Select the `context` parameter
3. Click Quick Look (eye icon) or press Space

Shows visual diagram:
- **Red**: previously focused view (search start)
- **Dotted red line**: search path
- **Purple**: focusable UIView regions in search path
- **Blue**: focusable UIFocusGuide regions in search path

## Debugging Focus Cascades (SwiftUI)

Focus cascades — where focus rapidly cycles through multiple items — are the hardest SwiftUI focus bugs to debug. Add structured logging to trace the exact sequence:

```swift
.onChange(of: focusedIndex) { old, new in
    logger.debug("[Focus] \(old.map(String.init) ?? "nil") → \(new.map(String.init) ?? "nil") active=\(activeIndex.map(String.init) ?? "nil")")
}
```

**What to look for in cascade logs:**
- `nil→0→nil→0→nil→0` = transient focus bouncing during pass-through navigation (see anti-pattern #29)
- `10→9→8→7→6→5→4→3→2→1→0` = rapid sequential cascade from `.disabled()` mass-toggle (see anti-pattern #25)
- `0→10 scrollTo 10 10→9` = `scrollTo` feedback loop disrupting focus (see anti-pattern #26)
- Same value set repeatedly with `active=` unchanged = `@Observable` same-value mutation (see anti-pattern #27)

**Production debug logging pattern:**
```swift
// ViewModel — log state transitions
logger.debug("[Focus] displayedTopicIndex \(old) → \(new)")
logger.debug("[Load] loadTopic(\(index)) start — isLoading=true, clips cleared")
logger.debug("[Load] loadTopic(\(index)) complete — clips=\(clips.count)")

// View — log focus with surrounding state
logger.debug("[Focus] sidebarFocus \(old) → \(new), isGridFocusable=\(isGridFocusable), clips=\(clips.count)")

// Sidebar — log container focus
logger.debug("[Focus] isContainerFocused \(isFocused)")

// Grid — log what's being rendered
logger.debug("[Render] clips=\(clips.count), isLoading=\(isLoading), showing=\(clips.isEmpty ? (isLoading ? "skeleton" : "empty") : "grid")")
```

Leave these logs in during development — they're invaluable for debugging on-device focus issues that don't reproduce in the simulator.

## Common Focus Issues Checklist

### Focus doesn't move at all
1. Is the target view focusable? (`canBecomeFocused`, or is it a Button/Cell?)
2. Is the target view visible? (not hidden, alpha > 0, in window)
3. Is `isUserInteractionEnabled = true` on the target AND all ancestors?
4. Is there a geometric path from current focus to target? (use Quick Look to see)
5. Is `shouldUpdateFocus(in:)` returning false somewhere in the chain?

### Focus jumps to wrong item
1. Missing `.focusSection()` on horizontal ScrollViews?
2. Are items geometrically aligned? Focus follows nearest-neighbor in swipe direction.
3. Is `remembersLastFocusedIndexPath` conflicting with manual focus management?
4. Is `preferredFocusEnvironments` returning stale references?

### Focus jitters / visual glitch
1. Are you using `frame.width` in transform calculations? Cache the resting width.
2. Is `prepareForReuse()` resetting all focus-related visual state?
3. Are focus animations using `addCoordinatedFocusingAnimations` (not plain UIView.animate)?
4. Is `layer.zPosition` managed to prevent overlap?
5. Are shadow animations using `CABasicAnimation` (not UIView.animate)?

### Focus lost after data reload
1. Is `reloadData()` called during an animation?
2. Is `remembersLastFocusedIndexPath` + offscreen reload causing stale index?
3. Is `shouldUpdateFocus(in:)` blocking during reload?
4. Did you call `setNeedsFocusUpdate()` + `updateFocusIfNeeded()` after reload?
5. Are you calling from the right focus environment (one that contains the focused view)?

### SwiftUI focus not working
1. Is `@FocusState` Optional when using `focused($binding, equals:)`?
2. Is `.focusScope(namespace)` on an ancestor of `prefersDefaultFocus`?
3. Is `.focusSection()` applied to the container, not individual buttons?
4. Is `.disabled()` being used? It removes views from tvOS focus chain. Gate the action inside the closure instead, or use dual `@FocusState` gating (anti-pattern #25).
5. Is `.focusable()` added to a Button? Remove it.

## Testing Focus

### UI Test Utilities

```swift
extension XCUIRemote {
    func press(_ button: XCUIRemote.Button, times: Int) {
        for _ in 0..<times {
            press(button)
            Thread.sleep(forTimeInterval: 0.3)
        }
    }
}

extension XCUIApplication {
    func focusedElement() -> XCUIElement {
        return descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
    }
}
```

### Focus navigation test pattern

```swift
func testFocusNavigationBetweenRows() {
    let remote = XCUIRemote.shared
    let app = XCUIApplication()

    // Navigate to first row item
    remote.press(.select)
    XCTAssertTrue(app.buttons["Row 0 Item 0"].hasFocus)

    // Move down to second row
    remote.press(.down)
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'Row 1'")).firstMatch.hasFocus)

    // Move back up
    remote.press(.up)
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'Row 0'")).firstMatch.hasFocus)
}
```

### Important: Simulator vs Hardware

Focus behavior differs between Simulator and Apple TV hardware:
- Simulator allows arrow key "press and hold" — hardware uses swipe gestures
- Timing of focus animations differs
- Some focus edge cases only reproduce on hardware
- Always verify critical focus flows on a physical device

## macOS Focus Debugging

### Inspecting First Responder

```
(lldb) po NSApp.keyWindow?.firstResponder
// Shows the currently focused view

(lldb) po NSApp.keyWindow?.firstResponder?.nextResponder
// Shows next in responder chain
```

### Debugging Key View Loop

Print the entire Tab order to verify correctness:

```swift
// Debug helper — call from lldb or a debug button
func printKeyViewLoop(from window: NSWindow) {
    guard let first = window.initialFirstResponder ?? window.contentView else { return }
    var current: NSView? = first
    var visited = Set<ObjectIdentifier>()
    repeat {
        guard let view = current else { break }
        let id = ObjectIdentifier(view)
        if visited.contains(id) {
            print("→ (loop complete, back to \(type(of: view)))")
            break
        }
        visited.insert(id)
        print("→ \(type(of: view)) canBecomeKeyView=\(view.canBecomeKeyView) acceptsFirstResponder=\(view.acceptsFirstResponder)")
        current = view.nextValidKeyView
    } while current != nil
}
```

### NSWindow.initialFirstResponder

```
(lldb) po window.initialFirstResponder
// View that receives focus when window first opens
// nil = no view gets automatic focus
```

If `initialFirstResponder` is nil, the window opens with no focused view. Set it in Interface Builder or programmatically:

```swift
override func windowDidLoad() {
    super.windowDidLoad()
    window?.initialFirstResponder = searchField
}
```

### Common macOS Focus Debugging Checklist

**View won't accept Tab focus:**
1. Is `acceptsFirstResponder` overridden to return `true`?
2. Is `canBecomeKeyView` returning `true`?
3. Is the view hidden, zero-alpha, or not in a window?
4. Is `isHidden` true on an ancestor?
5. Is the view in the key view loop? Check `nextKeyView` chain.
6. Is `recalculatesKeyViewLoop` enabled and possibly excluding the view geometrically?

**Focus ring not appearing:**
1. Is `focusRingType` set to `.none`?
2. Is `.focusEffectDisabled()` applied (SwiftUI)?
3. Is Full Keyboard Access enabled for non-text controls?
4. Is the view actually the first responder? Check `window.firstResponder`.

**Focus jumps to wrong view after sheet/alert:**
1. Is the previous first responder saved before showing the sheet?
2. Is `makeFirstResponder` called in the completion handler?
3. Does the saved view still exist in the hierarchy?

**Menu items don't respond to focused content:**
1. Is `focusedValue` set on the view hierarchy?
2. Is `@FocusedValue` reading the correct key in Commands?
3. Is the view in the key window (not main window behind a panel)?
4. Is `focusedSceneValue` needed for multi-window?

### Accessibility Inspector

Use Accessibility Inspector (Xcode > Open Developer Tool > Accessibility Inspector) to verify:
- Which element has keyboard focus
- Which element VoiceOver is reading
- Whether elements are properly labeled
- Focus order for Full Keyboard Access

### Debug with Notifications

```swift
// Track all focus changes in a window
NotificationCenter.default.addObserver(
    forName: NSWindow.didBecomeKeyNotification,
    object: nil, queue: .main
) { note in
    let window = note.object as? NSWindow
    print("Key window: \(window?.title ?? "nil"), firstResponder: \(window?.firstResponder ?? "nil" as Any)")
}
```
