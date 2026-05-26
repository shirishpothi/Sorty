# visionOS Focus and Hover Management

visionOS uses eye-tracking (gaze) as the primary targeting mechanism. Focus and hover are **related but distinct systems**.

## Core Concept: Gaze vs Focus vs Hover

- **Gaze = hover targeting**: Looking at an element triggers a *hover effect*. Your app **never receives raw gaze coordinates** (privacy by design).
- **Focus = keyboard/sequential navigation**: Traditional `@FocusState` / `UIFocusEnvironment` is for keyboard, VoiceOver, or Switch Control — not gaze.
- **Hover effects run out-of-process**: The system composites hover highlights outside your app sandbox. Your app learns *which* element was targeted only when the user pinches (confirms).

### Interaction Model
1. User **looks** at element (system renders hover highlight)
2. User **pinches** fingers (indirect tap gesture)
3. App receives tap event on targeted element

Alternative: Direct touch — reaching out and touching in volumes/immersive spaces.

### Critical Privacy Rule
`onHover(perform:)` does **NOT** fire from eye gaze on visionOS. It only fires from pointer devices (trackpad/mouse via Mac Virtual Display). This is the most common visionOS mistake.

## Hover Effect APIs (SwiftUI)

### Built-in Effects (visionOS 1.0+)

```swift
.hoverEffect(.automatic)  // System chooses best effect (default)
.hoverEffect(.highlight)  // Morphs platter behind view, shows light source
.hoverEffect(.lift)       // Slides under view, scales up with shadow
```

System controls (Button, Toggle, etc.) get hover effects automatically. Custom views with `.onTapGesture` do NOT — you must add `.hoverEffect()` explicitly.

### Custom Hover Effects (visionOS 2.0+)

```swift
.hoverEffect { effect, isActive, proxy in
    effect.animation(.easeInOut) {
        $0.scaleEffect(isActive ? 1.05 : 1.0)
           .opacity(isActive ? 1.0 : 0.8)
    }
}
```

Custom effects are **precomputed at view creation** and executed by the system compositor. No gaze data leaks to your app.

### HoverEffectGroup (visionOS 2.0+)

Coordinates multiple hover effects to activate together:

```swift
@Namespace var hoverGroup

HStack {
    Image(systemName: "star")
        .hoverEffect(in: HoverEffectGroup(hoverGroup))
    Text("Favorite")
        .hoverEffect(in: HoverEffectGroup(hoverGroup))
}
```

Looking at *any* view in the group activates all views' effects simultaneously.

### .contentShape(.hoverEffect, shape)

Customizes the hover highlight region without affecting the tap target:

```swift
Text("Custom Region")
    .padding()
    .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 10))
    .hoverEffect()
```

### .hoverEffectDisabled()

Disables hover effects on a view and its descendants:

```swift
Button("No hover") { }
    .hoverEffectDisabled(true)
```

### .defaultHoverEffect() (visionOS 2.0+)

Sets the default hover effect for a subtree. Children inherit unless overridden.

## RealityKit Entity Hover

### HoverEffectComponent (visionOS 1.0+)

For 3D entities in RealityView:

```swift
RealityView { content in
    let entity = ModelEntity(
        mesh: .generateSphere(radius: 0.2),
        materials: [SimpleMaterial(color: .blue, isMetallic: true)]
    )
    
    // THREE requirements for interactive entities:
    entity.components.set(InputTargetComponent())       // 1. Input receiver
    entity.components.set(CollisionComponent(           // 2. Hit-test shapes
        shapes: [ShapeResource.generateSphere(radius: 0.2)]
    ))
    entity.components.set(HoverEffectComponent())       // 3. Gaze highlight
    
    content.add(entity)
}
```

Missing `CollisionComponent` = hover never activates (gaze ray has nothing to hit).

visionOS 2.0+: Use `HoverState` in `ShaderGraphMaterial` for shader-driven hover effects on 3D content.

## @FocusState on visionOS

Works the same as other platforms — primarily for **keyboard focus** (Magic Keyboard connected) and accessibility:

```swift
@FocusState private var isSearchFocused: Bool

TextField("Search", text: $query)
    .focused($isSearchFocused)
```

When to use on visionOS:
- External Magic Keyboard connected
- VoiceOver or Switch Control active
- Programmatic focus for text fields

### .focusEffectDisabled() vs .hoverEffectDisabled()

These are **different things**:
- `.focusEffectDisabled()` — hides the keyboard focus ring (blue outline)
- `.hoverEffectDisabled()` — disables gaze hover highlight

## Window Focus vs Content Focus

### Shared Space
Multiple app windows coexist. Gaze activates the window being looked at. Window chrome (title bar, close button) gets system hover effects automatically.

### Ornaments
Toolbar-like controls attached to window edges. Participate in the same hover system:

```swift
.ornament(attachmentAnchor: .scene(.bottom)) {
    HStack {
        Button("Play") { }
        Button("Pause") { }
    }
    .glassBackgroundEffect()  // Required — ornaments don't get glass automatically
}
```

### Volumes
- Fixed scale (don't scale with distance like windows)
- 3D content: `HoverEffectComponent` on RealityKit entities
- SwiftUI overlays: standard `.hoverEffect()`
- No window bar by default

### Immersive Spaces
- One at a time; other apps hidden
- All interaction via gaze + pinch or direct touch
- No system window chrome — all focus/hover feedback must be explicitly added
- SwiftUI attachments in `RealityView` support `.hoverEffect()`

## External Keyboard on Vision Pro

When Magic Keyboard is connected:
- Tab/arrow key navigation activates
- `@FocusState` and `.focused()` control keyboard input target
- Keyboard focus ring (blue) appears alongside gaze hover highlights
- Both systems coexist — different elements can show hover highlight and keyboard focus simultaneously

## Accessibility

### VoiceOver
- Different finger pinches on different hands for navigation
- Accessibility labels and traits essential on both SwiftUI views and RealityKit entities

### Pointer Control
Alternative targeting instead of eyes:
- Head position, wrist position, index finger pointing
- Settings > Accessibility > Interaction > Pointer Control

### Dwell Control
Interact by looking at control for set duration (no pinch needed):
- Settings > Accessibility > AssistiveTouch > Dwell Control

### Switch Control
Works with external switches. RealityKit entities need accessibility properties.

## UIKit Focus Engine on visionOS

`UIFocusEnvironment`, `UIFocusSystem`, `UIFocusGuide` **do work** on visionOS:
- Activates with keyboard navigation, VoiceOver, or Switch Control
- Standard gaze interaction bypasses the focus engine (uses hover system instead)
- Cross-framework focus (UIKit + SpriteKit + SceneKit) supported

## Common Mistakes

### 1. Expecting onHover to fire from gaze
`onHover(perform:)` only triggers from pointer devices (trackpad/mouse). Use `.hoverEffect()` for gaze feedback.

### 2. Forgetting CollisionComponent on RealityKit entities
`HoverEffectComponent` alone does nothing without collision shapes for ray-casting.

### 3. Not adding .hoverEffect() to custom views
System controls get it free, but custom `View` with `.onTapGesture` needs explicit `.hoverEffect()` or it appears non-interactive.

### 4. Confusing .focusEffectDisabled() with .hoverEffectDisabled()
They disable different things (keyboard focus ring vs gaze hover highlight).

### 5. Making hover effects too prominent
Eyes move rapidly — distracting animations cause visual noise. Use subtle effects with appropriate delays.

### 6. Testing only in Simulator
Hover effects respond to actual eye gaze, which the simulator cannot replicate. Always test on device.

### 7. Forgetting .glassBackgroundEffect() on ornaments
Custom ornaments don't get glass material automatically.

## WWDC Sessions

| Session | Year | Key Content |
|---------|------|-------------|
| Design for spatial input | WWDC23 | Eye + hand interaction, hover design, privacy |
| Elevate your windowed app for spatial computing | WWDC23 | Hover effects, materials, ornaments |
| Meet SwiftUI for spatial computing | WWDC23 | Windows, volumes, hoverEffect |
| Create accessible spatial experiences | WWDC23 | VoiceOver, Switch Control, Pointer Control |
| Create custom hover effects in visionOS | WWDC24 | CustomHoverEffect, HoverEffectGroup |
| Design hover interactions for visionOS | WWDC25 | Advanced hover, persistence, media controls |
