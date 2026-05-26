# Common Layout Patterns and Focus (tvOS + macOS)

## Netflix/VOD Pattern: Table of Horizontal Collections

Each row is a table cell containing a horizontal collection view. This is the most common tvOS layout.

### SwiftUI

```swift
ScrollView(.vertical) {
    VStack(spacing: 40) {  // VStack, NOT LazyVStack — see warning below
        ForEach(categories) { category in
            VStack(alignment: .leading) {
                Text(category.title).font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 20) {  // LazyHStack is fine — heavy content stays lazy
                        ForEach(category.items) { item in
                            Button { select(item) } label: {
                                PosterCard(item: item)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                .focusSection()  // CRITICAL — prevents cross-row jumping
            }
        }
    }
}
.focusSection()  // Prevents focus escaping upward to tab bar
```

### Why VStack, NOT LazyVStack

**`LazyVStack` deallocates offscreen rows.** On tvOS, scrolling is focus-driven. When the user swipes up quickly, the focus engine searches upward geometrically — but the offscreen row views have been removed from the hierarchy. Focus finds nothing and jumps to the tab bar, skipping all content.

**`VStack` keeps all rows in the hierarchy.** The row containers are lightweight (just a title label + ScrollView wrapper). The expensive content (poster images, thumbnails) stays lazy inside each row's `LazyHStack`. This gives you the best of both worlds: focus-safe navigation with lazy-loaded heavy content.

Use `VStack` when:
- Row count is bounded (config-driven, typically 4-10 rows)
- Row containers are lightweight (the heavy content is inside lazy inner containers)

Use `UICollectionView` with `remembersLastFocusedIndexPath` when:
- Row count is unbounded (infinite scroll, feeds)
- VStack would load too much content eagerly

### UIKit

```swift
// UITableViewController where each cell contains a UICollectionView
class CatalogTableViewCell: UITableViewCell {
    let collectionView: UICollectionView

    override init(style:, reuseIdentifier:) {
        // Setup horizontal flow layout
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.remembersLastFocusedIndexPath = true
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [collectionView]
    }
}
```

The table view naturally isolates rows — vertical focus moves between table cells, horizontal within collection views.

## Sidebar + Content Pattern

### SwiftUI (basic sidebar pattern)

```swift
struct SidebarContentView: View {
    @FocusState var focusedSection: Section?
    @State var isExpanded = false

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack {
                ForEach(sections) { section in
                    Button(section.title) { selectedSection = section }
                        .focused($focusedSection, equals: section)
                }
            }
            .frame(width: isExpanded ? 300 : 80)
            .focusSection()
            .onChange(of: focusedSection) { old, new in
                if old != nil && new == nil { isExpanded = false }
                if old == nil && new != nil { isExpanded = true }
            }

            // Content
            ContentView(section: selectedSection)
                .focusSection()
        }
        .onExitCommand {
            if !isExpanded { isExpanded = true }
        }
    }
}
```

Key patterns:
- Each pane gets `.focusSection()`
- Sidebar expand/collapse driven by focus entering/leaving
- `.onExitCommand` returns focus to sidebar instead of exiting app
- `isInitialLoad` guard to prevent sidebar expanding on first appearance

### SwiftUI (Production pattern — dual @FocusState with .disabled() gating)

The basic sidebar pattern above has a critical flaw: when focus leaves (to grid, nav bar) and returns, `@FocusState` doesn't guarantee landing on the correct item. This production pattern solves it by combining three techniques:

```swift
struct TopicsSidebarView: View {
    @FocusState private var isContainerFocused: Bool   // Container-level
    @FocusState private var focusedIndex: Int?         // Per-item
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    
    let items: [Topic]
    let selectedIndex: Int
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button(item.title) { onSelect(index) }
                        .focused($focusedIndex, equals: index)
                        // KEY: Only the selected item is focusable when focus is OUTSIDE.
                        // All items are focusable when focus is INSIDE.
                        .disabled(!isContainerFocused && selectedIndex != index)
                }
            }
        }
        .focused($isContainerFocused)
        .scrollPosition($scrollPosition)  // Declarative — no ScrollViewReader
        .focusSection()
        .onChange(of: focusedIndex) { old, new in
            // Only act on within-sidebar navigation (both non-nil)
            guard let _ = old, let newIndex = new else { return }
            onFocusChanged(newIndex)
        }
    }
}
```

**Why this works:**
1. **`.disabled()` gating** — When focus is outside the sidebar, only the selected item is enabled. The focus engine can only land on it — no visible jump through wrong items.
2. **Container `@FocusState`** — `isContainerFocused` provides stable tracking of whether the sidebar has focus, without the instability of per-item nil checks.
3. **`ScrollPosition`** — Declarative scroll binding avoids `ScrollViewReader.scrollTo()` feedback loops (see anti-pattern #26).
4. **`onChange` guard** — Filters out transient focus touches during pass-through transitions (see anti-pattern #29).

### UIKit Sidebar (production pattern)

A reference UIKit codebase uses a fundamentally different approach that avoids SwiftUI's focus chain issues:

```swift
class TopicsSidebarViewController: UITableViewController {
    // KEY: Never disable individual rows — use container-level gating
    // and remembersLastFocusedIndexPath for restoration
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.remembersLastFocusedIndexPath = true
    }
    
    // Gate the CONTAINER, not individual items
    func setInteractionEnabled(_ enabled: Bool) {
        // Debounce rapid state changes with 0.5s timer
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.tableView.isUserInteractionEnabled = enabled
        }
    }
}
```

**Key differences from SwiftUI:**
- **Never disables individual rows** — avoids the mass-toggle cascade
- **`remembersLastFocusedIndexPath = true`** — built-in focus restoration (no SwiftUI equivalent)
- **Container-level `isUserInteractionEnabled`** — toggles the entire table, not individual cells
- **0.5s debounce** — prevents rapid state changes during navigation transitions
- **Built-in scroll fade** — `UITableView` has native gradient edge fading (SwiftUI requires manual mask)

### UIKit

Use `UIFocusGuide` to bridge the gap between sidebar and content:

```swift
let sidebarContentGuide = UIFocusGuide()
view.addLayoutGuide(sidebarContentGuide)
// Position between sidebar and content
sidebarContentGuide.preferredFocusEnvironments = [contentView]

// Update direction based on where focus came from
override func didUpdateFocus(in context: UIFocusUpdateContext, ...) {
    if context.previouslyFocusedView?.isDescendant(of: sidebarView) == true {
        sidebarContentGuide.preferredFocusEnvironments = [contentView]
    } else {
        sidebarContentGuide.preferredFocusEnvironments = [sidebarView]
    }
}
```

## Tab Bar Pattern

### SwiftUI

```swift
TabView(selection: $selectedTab) {
    HomeView().tabItem { Label("Home", systemImage: "house") }.tag(Tab.home)
    ShowsView().tabItem { Label("Shows", systemImage: "tv") }.tag(Tab.shows)
}
```

For custom tab bar (collapsible side tab bar pattern):
- Wrap tab buttons in `.focusSection()`
- Use `@FocusState` to track which tab is focused
- Expand/collapse on focus enter/leave
- Use `.onExitCommand` to bring focus back to tabs

### Tab Bar Focus Escape Detection (UIKit)

When hosting SwiftUI views inside UIKit tab bar controllers, detect when focus escapes from content to the tab bar. This is essential for fullscreen catalog views that need to collapse when the user navigates back to tabs:

```swift
class SwiftUIHomeViewController: UIHostingController<HomeView> {
    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard let tabBar = tabBarController?.tabBar else { return }
        let movedToTabBar = context.nextFocusedView?.isDescendant(of: tabBar) == true
        if movedToTabBar {
            // Collapse fullscreen catalog, restore default hero state
            viewModel.handleTabBarFocused()
        }
    }
}
```

Key rules:
- Use `guard let` — never allocate fallback objects in focus callbacks (see anti-pattern #17)
- Check `isDescendant(of:)` — don't compare view identity directly, tab bar items are nested
- Call on `super` first to preserve default behavior

### UIKit

Placeholder tabs (not yet implemented) should redirect focus back to the tab bar:

```swift
class PlaceholderTabViewController: UIViewController {
    private let focusGuide = UIFocusGuide()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addLayoutGuide(focusGuide)
        // Constrain to fill view
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let tabBar = tabBarController?.tabBar {
            focusGuide.preferredFocusEnvironments = [tabBar]
        }
    }
}
```

## Hero + Catalog Pattern

Large hero image at top, catalog rows below. Hero collapses when catalog gets focus.

### Focus coordination

```swift
// Track catalog focus to drive hero collapse
override func didUpdateFocus(in context: UIFocusUpdateContext, ...) {
    let focusInCatalog = context.nextFocusedView?.isDescendant(of: catalogView) == true
    let focusWasInCatalog = context.previouslyFocusedView?.isDescendant(of: catalogView) == true

    if focusInCatalog && !focusWasInCatalog {
        collapseHero(animated: true)
    } else if !focusInCatalog && focusWasInCatalog {
        expandHero(animated: true)
    }
}
```

Block focus during hero animation:

```swift
override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
    return !isAnimatingHeroTransition
}
```

## Scroll + Arrow Button Pattern

Horizontal shelf with left/right arrow buttons:

```swift
@FocusState private var buttonFocus: ScrollDirection?

HStack {
    VStack {
        button(.reverse, isDisabled: atStart)
        button(.forward, isDisabled: atEnd)
    }
    .focusSection()  // Buttons get own section

    ScrollView(.horizontal) {
        LazyHStack { /* items */ }
    }
    .focusSection()  // Scroll content gets own section
}

func button(_ direction: ScrollDirection, isDisabled: Bool) -> some View {
    Button {
        guard !isDisabled else { return }  // Gate the action, not the view
        scroll(direction)
    } label: { Image(systemName: "chevron.\(direction)") }
        .focused($buttonFocus, equals: direction)
        .opacity(isDisabled ? 0.5 : 1.0)
}
```

When a button becomes disabled after scrolling to the end, auto-move focus to the other button:

```swift
if viewModel.isFullyScrolled(direction: direction) {
    buttonFocus = direction.opposite
}
```

## Split Detail Pattern

Master list on left, detail on right. tvOS NavigationSplitView or manual split:

```swift
NavigationSplitView {
    List(items, selection: $selectedItem) { item in
        Text(item.title)
    }
    .focusSection()
} detail: {
    DetailView(item: selectedItem)
        .focusSection()
}
```

For custom implementation, use two `.focusSection()` panes and handle `.onExitCommand` to return to the master list.

## macOS Layout Patterns

### Sidebar + Content (NavigationSplitView)

The standard macOS document/navigation pattern. Focus moves between sidebar and content via Tab or mouse click.

```swift
NavigationSplitView {
    List(items, selection: $selectedItem) { item in
        Text(item.title)
    }
    .focusSection()  // macOS 14+ — Tab switches between sidebar and content
} detail: {
    if let item = selectedItem {
        DetailView(item: item)
            .focusSection()
    }
}
```

AppKit equivalent uses `NSSplitViewController`:

```swift
class MainSplitViewController: NSSplitViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Tab moves between split panes automatically
        // Arrow keys navigate within each pane
    }

    // Focus the sidebar's first item on Cmd+1
    @IBAction func focusSidebar(_ sender: Any?) {
        let sidebarVC = splitViewItems[0].viewController
        view.window?.makeFirstResponder(sidebarVC.view)
    }
}
```

### Toolbar + Content

macOS apps with toolbar items above the main content area. Toolbar focus requires Full Keyboard Access or Ctrl+F5.

```swift
struct ContentView: View {
    @FocusState private var isContentFocused: Bool

    var body: some View {
        VStack {
            // Content area gets focus by default
            DocumentEditor()
                .focusable()
                .focused($isContentFocused)
        }
        .toolbar {
            ToolbarItem {
                TextField("Search", text: $search)
                // Search field is Tab-focusable by default
            }
        }
        .onAppear { isContentFocused = true }
    }
}
```

### Multi-Window Document App

Each window has independent focus state. Menu commands target the key window.

```swift
@main
struct MyApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MyDocument()) { file in
            DocumentView(document: file.$document)
                .focusedSceneValue(\.activeDocument, file.document)
                // Each window publishes its document for menu commands
        }

        Settings {
            SettingsView()
            // Settings has its own focus scope — independent of documents
        }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.activeDocument) var document

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Format Selection") {
                document?.formatSelection()
            }
            .disabled(document == nil)
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}
```

### Preferences / Settings Window

```swift
Settings {
    TabView {
        GeneralSettingsView()
            .tabItem { Label("General", systemImage: "gear") }
        AdvancedSettingsView()
            .tabItem { Label("Advanced", systemImage: "gearshape.2") }
    }
    .frame(width: 450, height: 300)
}
// Tab key cycles through controls in the active settings tab
// Cmd+1/Cmd+2 switches between tabs
```

### Inspector Panel Pattern

Floating panel that doesn't steal focus from the main window:

```swift
// AppKit
let panel = NSPanel(contentRect: rect,
                    styleMask: [.titled, .closable, .utilityWindow],
                    backing: .buffered, defer: false)
panel.becomesKeyOnlyIfNeeded = true  // Don't steal focus
panel.isFloatingPanel = true          // Float above document windows
panel.orderFront(nil)                 // Show without making key

// SwiftUI — use Window scene
Window("Inspector", id: "inspector") {
    InspectorView()
}
.defaultSize(width: 250, height: 400)
```

### Source List + Editor + Inspector (Three-Column)

```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    // Source list (sidebar)
    List(projects, selection: $selectedProject) { project in
        Label(project.name, systemImage: "folder")
    }
    .focusSection()
} content: {
    // File list (middle)
    List(files, selection: $selectedFile) { file in
        Text(file.name)
    }
    .focusSection()
} detail: {
    // Editor (right)
    EditorView(file: selectedFile)
        .focusSection()
}
```

Tab moves between the three columns. Arrow keys navigate within each column. Each column maintains its own selection/focus independently.

## Scroll Edge Fade (tvOS)

UIKit's `UITableView` provides built-in gradient edge fading. SwiftUI has no equivalent — you must build it manually.

### `.scrollEdgeEffectStyle(.soft)` (tvOS 26+)

```swift
ScrollView(.vertical) {
    VStack { /* content */ }
}
.scrollEdgeEffectStyle(.soft, for: .all)
```

**Warning:** The tvOS 26 Liquid Glass effect makes this very subtle — often too subtle for media apps with dark backgrounds. Test carefully and fall back to manual mask if needed.

### Manual gradient mask (all tvOS versions)

Use `.mask()` with static gradient stops matching UIKit's `CAGradientLayer`:

```swift
struct StaticEdgeFadeMask: View {
    let fadeHeight: CGFloat = 40  // Match the UIKit reference's CAGradientLayer stop distance
    
    var body: some View {
        VStack(spacing: 0) {
            // Top fade
            LinearGradient(colors: [.clear, .black],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: fadeHeight)
            
            // Fully visible content area
            Color.black
            
            // Bottom fade
            LinearGradient(colors: [.black, .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: fadeHeight)
        }
    }
}

// Apply to ScrollView
ScrollView(.vertical) {
    VStack { /* sidebar items */ }
}
.mask { StaticEdgeFadeMask() }
```

**Important:** Use `.mask()`, not `.overlay()`. An overlay with solid colors shows a visible square against radial gradient backgrounds. `.mask()` works with any background because it only affects alpha.

### Dynamic scroll position tracking (tvOS 17+)

For fades that respond to scroll position (e.g., hiding top fade when at the top):

```swift
.onGeometryChange(for: CGFloat.self) { proxy in
    proxy.frame(in: .scrollView).minY
} action: { offset in
    isScrolledFromTop = offset < -10
}
```

### ScrollViewReader custom anchor for gentle scrolling

When programmatic scrolling is needed, use a custom anchor to avoid aggressive centering:

```swift
proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.7))
// y: 0.7 keeps the item in the lower third — gentler than .center
```

## Focus Scale Matching (tvOS)

UIKit apps typically use `adjustsImageWhenAncestorFocused` which applies ~1.13x scale with parallax. SwiftUI `scaleEffect` should match:

| Element | UIKit (Flagship) | SwiftUI (Recommended) |
|---------|-----------------|----------------------|
| Clip card | System focus (~1.13 + parallax) | `scaleEffect(1.13)` |
| Show poster | System focus (~1.13 + parallax) | `scaleEffect(1.13)` |
| Sidebar row | No scale — color/pill only | No scale — color/pill only |
| Shadow (focused) | System parallax shadow | opacity 0.5, radius 24, y 18 |

When using 1.13 scale, increase vertical padding around rows to accommodate growth: `card_height * 0.13 / 2 ≈ 26pt` on each side (round up to 40pt for safety).
