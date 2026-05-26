# UIKit Focus APIs for tvOS

## UIFocusEnvironment Protocol

Conforming classes: `UIView`, `UIViewController`, `UIWindow`, `UIPresentationController`.

### preferredFocusEnvironments

Ordered array of where focus should go. The focus engine follows the preferred focus chain: Window -> Root VC -> Child VC -> View -> Subview, each returning its `preferredFocusEnvironments`, until reaching a focusable leaf.

```swift
override var preferredFocusEnvironments: [UIFocusEnvironment] {
    if shouldFocusSearch {
        return [searchButton]
    }
    return [collectionView]
}
```

### When to override `preferredFocusEnvironments`

Override on any tvOS `UIViewController` whose `view` contains more than one focusable subview at the same level. Without the override, the focus engine picks the geometrically-first focusable view, which is almost never the intended primary CTA.

Triggers that require an override:

- Vertical or horizontal `UIStackView` of multiple `UIButton`s.
- A view containing both a focusable list (`UITableView`, `UICollectionView`) and standalone buttons.
- A screen whose primary CTA is conditional on a flag, remote config, or async data — return the conditionally-correct environment from the override.
- A modal/sheet presented over another VC where the system would otherwise restore focus to the presenter.

For a conditional CTA, branch inside the override and pair with `setNeedsFocusUpdate()` + `updateFocusIfNeeded()` when the condition changes after the VC is on screen. Call those from the VC that currently contains focus — see "Programmatic focus updates" below and anti-pattern #7.

```swift
override var preferredFocusEnvironments: [UIFocusEnvironment] {
    if showPrimaryCTA {
        return [primaryCTAButton]
    }
    return [secondaryButton]
}
```

The system reads `preferredFocusEnvironments` walking the chain: window -> root VC -> child VC -> view -> subview. Each step returns its preferred environments until reaching a focusable leaf. Returning a focusable `UIButton` directly (not wrapped) is correct — `UIButton` already conforms to `UIFocusEnvironment`.

### shouldUpdateFocus(in:)

Validate or cancel focus moves. Called on EVERY focus environment in the hierarchy containing both the previously focused and next focused views. If ANY returns false, the move is canceled.

```swift
override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
    // Block focus during animations
    if isAnimating { return false }
    
    // Block specific transitions
    if context.nextFocusedView == someViewToBlock {
        return false
    }
    return true
}
```

### didUpdateFocus(in:with:)

React to focus changes and coordinate animations.

```swift
override func didUpdateFocus(in context: UIFocusUpdateContext,
                             with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    
    if self == context.nextFocusedView {
        coordinator.addCoordinatedFocusingAnimations({ animCtx in
            self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            self.layer.zPosition = 1
        }, completion: nil)
    } else if self == context.previouslyFocusedView {
        coordinator.addCoordinatedUnfocusingAnimations({ animCtx in
            self.transform = .identity
            self.layer.zPosition = 0
        }, completion: nil)
    }
}
```

Animation targeting rules:
- `addCoordinatedFocusingAnimations` — runs with focusing timing (prominent)
- `addCoordinatedUnfocusingAnimations` — runs with unfocusing timing (subtle)
- `UIFocusAnimationContext.duration` provides timing for synchronized nested animations

### Programmatic focus updates

The ONLY correct way to move focus programmatically in UIKit:

```swift
// 1. Store desired target
var pendingFocusTarget: UIView?

// 2. Override preferredFocusEnvironments
override var preferredFocusEnvironments: [UIFocusEnvironment] {
    if let target = pendingFocusTarget {
        return [target]
    }
    return super.preferredFocusEnvironments
}

// 3. Trigger the update
pendingFocusTarget = someButton
setNeedsFocusUpdate()
updateFocusIfNeeded()
```

Critical: `setNeedsFocusUpdate()` ONLY works if the calling focus environment currently contains the focused view.

## UIFocusGuide

Invisible rectangular area that redirects focus to real views. Use to bridge gaps between non-adjacent focusable regions.

```swift
let focusGuide = UIFocusGuide()
view.addLayoutGuide(focusGuide)

// Position with Auto Layout
NSLayoutConstraint.activate([
    focusGuide.leadingAnchor.constraint(equalTo: menuView.trailingAnchor),
    focusGuide.trailingAnchor.constraint(equalTo: contentView.leadingAnchor),
    focusGuide.topAnchor.constraint(equalTo: view.topAnchor),
    focusGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor)
])

// Redirect focus
focusGuide.preferredFocusEnvironments = [contentView]
```

Update dynamically based on context:
```swift
override func didUpdateFocus(in context: UIFocusUpdateContext,
                             with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    // Redirect guide toward wherever focus just came from
    if context.previouslyFocusedView === menuView {
        focusGuide.preferredFocusEnvironments = [contentView]
    } else {
        focusGuide.preferredFocusEnvironments = [menuView]
    }
}
```

Properties:
- `preferredFocusEnvironments: [UIFocusEnvironment]` — redirect targets (ordered)
- `isEnabled: Bool` — enable/disable
- Do NOT use deprecated `preferredFocusedView`

## canBecomeFocused

Override on custom UIView subclasses to make them focusable.

```swift
override var canBecomeFocused: Bool { return true }
```

Built-in focusable: UIButton, UITextField, UITableViewCell, UICollectionViewCell, UITextView, UISegmentedControl, UISearchBar.

Not focusable by default: UILabel, UIImageView, custom UIView.

## isTransparentFocusItem

When true, the item can receive focus but items behind it can also become focused. Used for invisible focus anchors.

```swift
override var isTransparentFocusItem: Bool { return true }
```

## remembersLastFocusedIndexPath

```swift
collectionView.remembersLastFocusedIndexPath = true
```

When true, `indexPathForPreferredFocusedView(in:)` only gets called the FIRST time (before any index is remembered). Combine with manual tracking:

```swift
func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
    return lastFocusedIndexPath
}
```

## UIFocusSystem

```swift
// Get focus system for an environment
let focusSystem = UIFocusSystem.focusSystem(for: self)

// Register custom focus sounds
UIFocusSystem.register(soundFileURL, forSoundIdentifier: .default)
```

### soundIdentifierForFocusUpdate(in:)

Control per-item focus sounds. Sounds auto-modulate volume based on movement speed and pan based on screen position.

```swift
override func soundIdentifierForFocusUpdate(in context: UIFocusUpdateContext) -> UIFocusSoundIdentifier? {
    return .none  // Suppress sound for this item
}
```

## UIFocusMovementDidFail Notification

Detect when user tries to move focus but can't (swipes into a wall).

```swift
NotificationCenter.default.addObserver(
    self, selector: #selector(focusMovementFailed),
    name: UIFocusSystem.movementDidFailNotification, object: nil
)
```

## Collection/Table View Focus Delegates

```swift
// UICollectionViewDelegate
func collectionView(_ collectionView: UICollectionView,
    canFocusItemAt indexPath: IndexPath) -> Bool

func collectionView(_ collectionView: UICollectionView,
    didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
    with coordinator: UIFocusAnimationCoordinator)

func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath?

// UITableViewDelegate — same pattern
func tableView(_ tableView: UITableView,
    canFocusRowAt indexPath: IndexPath) -> Bool
```
