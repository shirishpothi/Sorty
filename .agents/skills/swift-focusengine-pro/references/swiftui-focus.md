# SwiftUI Focus APIs for tvOS

## @FocusState

Tracks and programmatically controls which view has focus. Available tvOS 15+.

### Boolean form — single focusable view
```swift
@FocusState private var isFieldFocused: Bool

TextField("Search", text: $query)
    .focused($isFieldFocused)

// Move focus:
isFieldFocused = true
```

### Enum form — multiple focusable views
```swift
enum Field: Hashable {
    case email, password
}

@FocusState private var focusedField: Field?  // MUST be Optional

TextField("Email", text: $email)
    .focused($focusedField, equals: .email)
SecureField("Password", text: $password)
    .focused($focusedField, equals: .password)

// Move focus:
focusedField = .password
// Remove focus from this scope:
focusedField = nil
```

### Syncing with ViewModel
```swift
// View extension for bidirectional sync
extension View {
    func sync<T: Equatable>(_ binding: Binding<T>, with focusState: FocusState<T>) -> some View {
        onChange(of: binding.wrappedValue) { _, newValue in
            focusState.wrappedValue = newValue
        }
        .onChange(of: focusState.wrappedValue) { _, newValue in
            binding.wrappedValue = newValue
        }
    }
}

// Usage:
@FocusState var focusedSection: SettingsSection?

var body: some View {
    content
        .sync($viewModel.focusedSection, with: _focusedSection)
}
```

## focusSection()

Makes a container's entire frame act as one large focusable region for the focus engine. This is the SwiftUI equivalent of `UIFocusGuide`.

Without it, focus movement only works between geometrically adjacent focusable views. With it, the focus engine treats the container's frame as scannable.

```swift
HStack {
    VStack {
        Button("A") {}
        Button("B") {}
    }
    .focusSection()  // Left column

    VStack {
        Button("C") {}
        Button("D") {}
    }
    .focusSection()  // Right column
}
```

### When to use focusSection()
- Every horizontal ScrollView inside a vertical layout (prevents cross-row jumping)
- Sidebar/content split layouts (each pane gets its own section)
- Tab bar areas separate from content
- Any group of focusable items that should be navigated as a unit

### Gotcha
`focusSection()` needs the container to have sufficient frame size. If buttons don't fill the space, add `Spacer()` inside the container to expand its bounds.

## prefersDefaultFocus(_:in:) + focusScope(_:)

Controls which view gets focus by default within a namespace scope. tvOS and watchOS only.

```swift
@Namespace private var namespace
@Environment(\.resetFocus) var resetFocus

VStack {
    Button("Search") { }
        .prefersDefaultFocus(shouldFocusSearch, in: namespace)
    Button("Play") { }
        .prefersDefaultFocus(!shouldFocusSearch, in: namespace)
    Button("Reset Focus") {
        resetFocus(in: namespace)
    }
}
.focusScope(namespace)
```

Rules:
- `focusScope(namespace)` MUST be on an ancestor of views using `prefersDefaultFocus`
- `resetFocus(in:)` re-evaluates preferences and moves focus
- Does NOT work inside ScrollView — use `defaultFocus` instead

## defaultFocus(_:_:priority:)

Modern cross-platform replacement. Works inside ScrollView.

```swift
@FocusState private var focusedField: Field?

VStack { ... }
    .defaultFocus($focusedField, .email, priority: .userInitiated)
```

Priority levels:
- `.automatic` — default, system may override
- `.userInitiated` — forces focus even when system would choose differently (use sparingly)

## onMoveCommand

Custom directional navigation when geometric focus fails.

```swift
.onMoveCommand { direction in
    switch direction {
    case .left: focusedField = .sidebar
    case .right: focusedField = .content
    case .down: focusedField = .row1
    default: break
    }
}
```

## onExitCommand

Intercepts Menu/Back button press. Essential for sidebar patterns.

```swift
.onExitCommand {
    if !sidebarExpanded {
        sidebarExpanded = true  // Expand sidebar instead of exiting
    }
}
```

## focusable() and focusable(interactions:)

Makes any view capable of receiving focus.

```swift
.focusable()                        // All interactions
.focusable(interactions: .edit)     // Text-like editing
.focusable(interactions: .activate) // Button-like activation
.focusable(isEnabled)               // Conditional
```

Do NOT apply to Button, NavigationLink, or Toggle — they are already focusable.

## isFocused Environment

Read-only focus state. Returns true if nearest focusable ancestor is focused.

```swift
@Environment(\.isFocused) var isFocused
```

Used in custom ButtonStyles for visual feedback. See `references/focus-styling.md`.

## Hover Effects (tvOS 17+)

```swift
.hoverEffect(.lift)       // Default for Buttons — lifts the view
.hoverEffect(.highlight)  // Adds perspective shift + specular shine (great for artwork)
.focusEffectDisabled()     // Disables default focus appearance
```

## AutoFocus Pattern

One-time programmatic focus on screen load, coordinated with layout completion:

```swift
class AutoFocusManager: ObservableObject {
    @Published var shouldAutoFocus = true
    private let subject = PassthroughSubject<Void, Never>()
    var publisher: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
    private var hasTriggered = false

    func trigger() {
        guard shouldAutoFocus, !hasTriggered else { return }
        subject.send()
        hasTriggered = true
        shouldAutoFocus = false
    }

    func reset() {
        shouldAutoFocus = true
        hasTriggered = false
    }
}

// In parent view — trigger after layout completes:
.onPreferenceChange(LayoutCompleteKey.self) { complete in
    if complete { autoFocusManager.trigger() }
}

// In child view — receive and set focus:
.onReceive(autoFocusManager.publisher) { _ in
    focusedField = .mainContent
}
```
