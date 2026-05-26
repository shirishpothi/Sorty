# Async Focus Patterns

Focus updates must happen on the main thread. Coordinating focus with async data loading, navigation, and animations requires careful sequencing.

## @MainActor and Focus Updates

All focus state changes must happen on `@MainActor`. SwiftUI's `@FocusState` is already main-actor-isolated, but UIKit focus updates called from async contexts can silently fail.

### SwiftUI

```swift
@MainActor
struct ContentView: View {
    @FocusState private var focusedItem: String?
    @State private var items: [String] = []
    
    var body: some View {
        VStack {
            ForEach(items, id: \.self) { item in
                Button(item) { }
                    .focused($focusedItem, equals: item)
            }
        }
        .task {
            items = await loadItems()
            // Safe — .task runs on @MainActor for SwiftUI views
            focusedItem = items.first
        }
    }
}
```

### UIKit

```swift
func loadAndFocus() {
    Task {
        let data = await fetchData()
        
        // BAD — may not be on main actor
        // self.setNeedsFocusUpdate()
        
        // GOOD — explicitly dispatch to main
        await MainActor.run {
            self.dataSource.apply(data)
            self.collectionView.layoutIfNeeded()
            self.setNeedsFocusUpdate()
            self.updateFocusIfNeeded()
        }
    }
}
```

## Focus After Data Load

The most common async focus bug: data loads, view updates, but focus either resets to the top or points at a stale index.

### Pattern: Deferred Focus Restoration

```swift
struct CatalogView: View {
    @FocusState private var focusedID: String?
    @State private var items: [Item] = []
    @State private var pendingFocusID: String?
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(items) { item in
                    CardView(item: item)
                        .focused($focusedID, equals: item.id)
                }
            }
        }
        .onChange(of: items) { _, newItems in
            // Restore focus after data update
            if let pending = pendingFocusID, newItems.contains(where: { $0.id == pending }) {
                focusedID = pending
                pendingFocusID = nil
            }
        }
    }
    
    func refresh() async {
        pendingFocusID = focusedID  // Save before reload
        items = await fetchItems()
        // Focus restoration happens in onChange
    }
}
```

### Pattern: UIKit Safe Reload with Focus Lock

```swift
class CatalogViewController: UIViewController {
    private var allowsFocusUpdate = true
    private var savedIndexPath: IndexPath?
    
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        return allowsFocusUpdate
    }
    
    func reloadPreservingFocus() async {
        // Save current focus position
        savedIndexPath = collectionView.indexPathsForVisibleItems
            .first { collectionView.cellForItem(at: $0)?.isFocused == true }
        
        // Lock focus during reload
        allowsFocusUpdate = false
        
        let newData = await fetchData()
        
        await MainActor.run {
            dataSource.apply(newData, animatingDifferences: false)
            collectionView.layoutIfNeeded()
            
            // Unlock and restore
            allowsFocusUpdate = true
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
    }
    
    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        return savedIndexPath
    }
}
```

## Focus After Navigation

### NavigationStack Pop (SwiftUI)

When popping back in a `NavigationStack`, SwiftUI does NOT automatically restore focus to the item that triggered the push. You must track and restore it manually.

```swift
struct ListView: View {
    @FocusState private var focusedID: String?
    @State private var lastSelectedID: String?
    
    var body: some View {
        NavigationStack {
            List(items) { item in
                NavigationLink(value: item) {
                    Text(item.title)
                }
                .focused($focusedID, equals: item.id)
            }
            .navigationDestination(for: Item.self) { item in
                DetailView(item: item)
            }
            .onAppear {
                // Restore focus when coming back
                if let lastID = lastSelectedID {
                    focusedID = lastID
                }
            }
        }
    }
}
```

### Tab Switching (tvOS)

Focus state is per-tab. Switching tabs and switching back should restore the previously focused item in that tab. Use `@FocusState` with `onAppear`/`onDisappear` to save and restore.

```swift
struct TabContentView: View {
    @FocusState private var focusedItem: String?
    @State private var savedFocusItem: String?
    
    var body: some View {
        content
            .onDisappear {
                savedFocusItem = focusedItem
            }
            .onAppear {
                if let saved = savedFocusItem {
                    focusedItem = saved
                }
            }
    }
}
```

## withAnimation and Focus

### SwiftUI

Setting `@FocusState` inside `withAnimation` animates the focus change:

```swift
withAnimation(.easeInOut(duration: 0.3)) {
    focusedItem = "newItem"
}
```

But setting focus in a `Task` after `withAnimation` completes can cause visual glitches:

```swift
// BAD — focus set after animation context ends
withAnimation {
    showNewSection = true
}
Task {
    focusedItem = "firstItemInNewSection"  // May flash or not animate
}

// GOOD — set focus in same animation transaction
withAnimation {
    showNewSection = true
    focusedItem = "firstItemInNewSection"
}
```

### UIKit

`setNeedsFocusUpdate()` coordinates with `UIView.animate` when called inside `addCoordinatedFocusingAnimations`:

```swift
func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    coordinator.addCoordinatedFocusingAnimations({ animContext in
        // These animate in sync with the focus change
        self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
    }, completion: nil)
}
```

## Concurrent Data Loads

When multiple data sources load simultaneously, coordinate which one gets to set focus.

```swift
struct HomeView: View {
    @FocusState private var focusedSection: SectionID?
    @State private var heroLoaded = false
    @State private var catalogLoaded = false
    
    var body: some View {
        VStack {
            HeroSection()
                .focused($focusedSection, equals: .hero)
                .task {
                    await loadHero()
                    heroLoaded = true
                }
            
            CatalogSection()
                .focused($focusedSection, equals: .catalog)
                .task {
                    await loadCatalog()
                    catalogLoaded = true
                }
        }
        .onChange(of: heroLoaded) { _, loaded in
            if loaded && focusedSection == nil {
                focusedSection = .hero  // Hero gets priority
            }
        }
    }
}
```

### Priority Rule
Establish a clear focus priority when multiple sections load at different times. Without it, the last section to load wins focus, causing visible focus jumps.

## Task Cancellation and Focus

When a `Task` is cancelled (view disappears, user navigates away), any pending focus update in that task should be skipped.

```swift
.task {
    let items = await loadItems()
    
    // Check cancellation before setting focus
    guard !Task.isCancelled else { return }
    
    self.items = items
    focusedItem = items.first?.id
}
```

In UIKit, cancel tasks in `viewWillDisappear` to prevent focus updates on an off-screen view controller:

```swift
private var loadTask: Task<Void, Never>?

override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    loadTask = Task { await loadAndFocus() }
}

override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    loadTask?.cancel()
}
```

## Debouncing Focus Updates

Rapid state changes (search results, filter updates) can trigger focus updates on every keystroke. Debounce to prevent focus flickering.

```swift
struct SearchView: View {
    @FocusState private var focusedResult: String?
    @State private var results: [String] = []
    @State private var searchTask: Task<Void, Never>?
    
    func search(query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            
            results = await performSearch(query)
            focusedResult = results.first
        }
    }
}
```

## @Observable and Focus

### Same-value mutation guard

With `@Observable` (iOS 17+, tvOS 17+), property setters always call `withMutation()` even when the value hasn't changed. This fires observation notifications, causing SwiftUI to re-evaluate `body`, which can disrupt the focus engine mid-navigation.

```swift
// BAD — every call fires observation, even no-ops
@Observable class ViewModel {
    var selectedIndex: Int = 0
    
    func indexFocused(_ index: Int) {
        selectedIndex = index  // Always fires, even if index == selectedIndex
    }
}

// GOOD — guard against same-value
func indexFocused(_ index: Int) {
    guard selectedIndex != index else { return }
    selectedIndex = index
}
```

This is critical in focus callbacks where rapid traversal may set the same value repeatedly.

### @ObservationIgnored for non-UI state

Properties that drive focus logic but shouldn't trigger view updates should use `@ObservationIgnored`:

```swift
@Observable class ViewModel {
    @ObservationIgnored private var paginationTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    
    var clips: [Clip] = []  // This should trigger UI updates
}
```

## ScrollTo Feedback Loops

Imperative `ScrollViewReader.scrollTo()` inside `onChange(of: focusedItem)` creates cascading focus updates:

1. Focus moves → `onChange` fires → `scrollTo()` animates viewport
2. Viewport animation repositions items under the focus cursor
3. Focus engine recalculates → finds new nearest item → focus moves
4. Goto 1

**Fix:** Replace `ScrollViewReader` with declarative `ScrollPosition` (tvOS 17+):

```swift
// BAD — imperative scrollTo fights the focus engine
ScrollViewReader { proxy in
    ScrollView {
        ForEach(items) { item in
            Button(item.title) { }
                .focused($focusedItem, equals: item.id)
        }
    }
    .onChange(of: focusedItem) { _, new in
        proxy.scrollTo(new, anchor: .center)  // Triggers cascade!
    }
}

// GOOD — declarative ScrollPosition coordinates with focus atomically
@State private var scrollPosition = ScrollPosition(idType: String.self)

ScrollView {
    ForEach(items) { item in
        Button(item.title) { }
            .focused($focusedItem, equals: item.id)
    }
}
.scrollPosition($scrollPosition)
```

If `ScrollViewReader` is required (e.g., tvOS 16 support), disable animation on programmatic scrolls and use a debounce:

```swift
.onChange(of: focusedItem) { _, new in
    guard let id = new else { return }
    // No withAnimation — prevents disrupting focus engine
    proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.7))
}
```

## Common Mistakes

### 1. Setting focus before view is in hierarchy
Setting `@FocusState` before the target view appears in the hierarchy does nothing. Use `onAppear` or `task` to defer.

### 2. Focus update in detached Task
A detached `Task` does not inherit the main actor context. Focus updates inside `Task.detached` will not work without explicit `@MainActor` dispatch.

### 3. Race condition between multiple .task modifiers
Multiple `.task` modifiers on sibling views can complete in any order. Each may try to claim focus, causing visible focus jumping.

### 4. Not checking Task.isCancelled before focus update
Setting focus on a view that has already disappeared (task was not cancelled) causes no crash but wastes cycles and can cause brief visual artifacts.

### 5. Calling setNeedsFocusUpdate from background thread
UIKit focus updates from a background thread silently fail. Always use `await MainActor.run { }` or `DispatchQueue.main.async { }`.
