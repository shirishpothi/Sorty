# Focus Restoration After Data Updates

## The Problem

When data reloads (API response, state change), the previously focused item may change identity or disappear. Focus jumps to the first item or an unexpected location.

## SwiftUI Pattern

### Save and restore @FocusState

```swift
@FocusState var focusedID: String?
@State private var savedFocusID: String?

func loadData() async {
    savedFocusID = focusedID
    await viewModel.refresh()
    // Restore on next run loop
    Task { @MainActor in
        focusedID = savedFocusID
    }
}
```

### Using identifiable items with @FocusState

If list items have stable IDs, focus restoration is automatic as long as the ID persists:

```swift
ForEach(items) { item in
    Button(item.title) { ... }
        .focused($focusedItem, equals: item.id)
}
```

When the data updates but the same IDs exist, `@FocusState` maintains focus. When the focused item's ID disappears, focus falls to the next geometric candidate.

### AutoFocus after navigation return

When returning from a detail view, use the AutoFocusManager pattern to restore focus to the previously selected item:

```swift
.onAppear {
    if let savedID = viewModel.lastViewedItemID {
        focusedItem = savedID
    }
}
```

## UIKit Pattern

### Manual tracking + preferredFocusEnvironments

```swift
var lastFocusedIndexPath: IndexPath?

// Track in delegate
func collectionView(_ collectionView: UICollectionView,
    didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
    with coordinator: UIFocusAnimationCoordinator) {
    lastFocusedIndexPath = context.nextFocusedIndexPath
}

// Restore via preferred focus
override var preferredFocusEnvironments: [UIFocusEnvironment] {
    if let indexPath = lastFocusedIndexPath,
       let cell = collectionView.cellForItem(at: indexPath) {
        return [cell]
    }
    return super.preferredFocusEnvironments
}

// After reload
func reloadAndRestore() {
    collectionView.reloadData()
    collectionView.layoutIfNeeded()
    setNeedsFocusUpdate()
    updateFocusIfNeeded()
}
```

### Safe reload pattern — gate focus during reload

```swift
private var allowsFocusUpdate = true

override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
    return allowsFocusUpdate
}

func safeReload() {
    allowsFocusUpdate = false
    collectionView.reloadData()
    collectionView.layoutIfNeeded()
    allowsFocusUpdate = true
    setNeedsFocusUpdate()
    updateFocusIfNeeded()
}
```

### Use reloadItems(at:) instead of reloadData() when possible

`reloadData()` destroys `remembersLastFocusedIndexPath` state when the collection view is offscreen. Prefer granular updates:

```swift
// BAD — destroys focus memory when offscreen
collectionView.reloadData()

// GOOD — preserves focus memory
collectionView.reloadItems(at: changedIndexPaths)

// Or use performBatchUpdates for insert/delete/move
collectionView.performBatchUpdates({
    collectionView.insertItems(at: newIndexPaths)
    collectionView.deleteItems(at: removedIndexPaths)
}, completion: nil)
```

## Row offset tracking (table-of-collections pattern)

When a table view contains collection views per row, save each row's scroll offset so returning to a row restores its position:

```swift
private var rowContentOffsets: [Int: CGPoint] = [:]

// Save when leaving a row
func didUpdateFocus(in context: UIFocusUpdateContext, ...) {
    if let previousRow = previousRowIndex,
       let collectionView = collectionViewForRow(previousRow) {
        rowContentOffsets[previousRow] = collectionView.contentOffset
    }
}

// Restore when entering a row
func willDisplay(cell:, forRowAt indexPath:) {
    if let offset = rowContentOffsets[indexPath.row] {
        cell.collectionView.contentOffset = offset
    }
}
```

## macOS Focus Restoration

### Window First Responder Persistence

macOS automatically preserves the first responder per window. Switching between windows restores focus in each. However, rebuilding the view hierarchy (e.g., SwiftUI re-rendering a view) can reset the first responder.

### Save/Restore Around Sheets and Alerts (AppKit)

```swift
// Save before showing sheet
let savedResponder = window.firstResponder

window.beginSheet(sheetWindow) { response in
    // Restore after sheet dismissal
    self.window.makeFirstResponder(savedResponder)
}
```

SwiftUI `.sheet()` handles this automatically — focus returns to the presenting view on dismiss.

### NSDocument Focus After Save/Revert

When a document reverts (`revert(toContentsOf:ofType:)`), the view hierarchy may reload. Track and restore the focused field:

```swift
override func revert(toContentsOf url: URL, ofType typeName: String) throws {
    let savedResponder = windowForSheet?.firstResponder
    try super.revert(toContentsOf: url, ofType: typeName)
    // Defer to next run loop — views need time to rebuild
    DispatchQueue.main.async {
        self.windowForSheet?.makeFirstResponder(savedResponder)
    }
}
```

## Handling focus during async transitions

When transitioning between states (loading -> loaded, collapsed -> expanded):

```swift
// Block focus during transition
isAnimatingTransition = true

UIView.animate(withDuration: 0.3, animations: {
    // Layout changes
}) { _ in
    self.isAnimatingTransition = false
    self.setNeedsFocusUpdate()
    self.updateFocusIfNeeded()
}

override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
    return !isAnimatingTransition
}
```
