# RealityKit Focus and Hover (visionOS)

RealityKit entities use a separate hover/interaction system from SwiftUI views. Getting 3D content to respond to gaze requires explicit component setup.

## Entity Interaction Requirements

Every interactive RealityKit entity needs **three components**:

```swift
let entity = ModelEntity(
    mesh: .generateBox(size: 0.3),
    materials: [SimpleMaterial(color: .blue, isMetallic: true)]
)

entity.components.set(InputTargetComponent())           // Receives input events
entity.components.set(CollisionComponent(               // Hit-testing for gaze ray
    shapes: [ShapeResource.generateBox(size: [0.3, 0.3, 0.3])]
))
entity.components.set(HoverEffectComponent())           // Visual gaze feedback
```

Missing any one of these = the entity is invisible to gaze interaction.

### Common Setup Mistakes

**Collision shape mismatch:** The collision shape must approximate the visual mesh. A tiny collision shape on a large model means gaze only registers on a small area.

```swift
// BAD — collision sphere on a box model
entity.components.set(CollisionComponent(
    shapes: [ShapeResource.generateSphere(radius: 0.05)]  // Too small
))

// GOOD — collision matches visual geometry
entity.components.set(CollisionComponent(
    shapes: [ShapeResource.generateBox(size: [0.3, 0.3, 0.3])]
))
```

**Forgetting InputTargetComponent on child entities:** In an entity hierarchy, the entity that receives gestures needs `InputTargetComponent`. If only the parent has it, gestures may not route correctly to children.

**Entity not added to scene:** Components on entities that are not part of the `RealityView` content hierarchy do nothing.

## HoverEffectComponent Styles

### Default (visionOS 1.0+)

```swift
entity.components.set(HoverEffectComponent())  // System default highlight
```

### Spotlight Effect (visionOS 2.0+)

```swift
entity.components.set(HoverEffectComponent(
    .spotlight(SpotlightHoverEffectStyle(
        color: .white,
        strength: 1.0
    ))
))
```

### Shader Effect (visionOS 2.0+)

For custom shader-driven hover, use `HoverState` in your `ShaderGraphMaterial`:

```swift
// In Reality Composer Pro:
// 1. Add HoverState node to shader graph
// 2. Connect HoverState.isActive output to material properties
// 3. Use HoverState.position for localized effects (glow follows gaze point)

let material = try await ShaderGraphMaterial(
    named: "/Root/HoverGlowMaterial",
    from: "Scene.usda"
)
entity.model?.materials = [material]
entity.components.set(HoverEffectComponent(.shader(.default)))
```

`HoverState` provides:
- `isActive` (Bool) — whether gaze is on the entity
- `position` (float2) — UV coordinate of gaze point on entity surface

### Highlight Effect (visionOS 2.0+)

```swift
entity.components.set(HoverEffectComponent(
    .highlight(HighlightHoverEffectStyle(
        color: .systemBlue,
        strength: 0.8
    ))
))
```

## Gesture Handling on Entities

### Tap Gesture

```swift
RealityView { content in
    content.add(entity)
}
.gesture(
    SpatialTapGesture()
        .targetedToEntity(entity)
        .onEnded { value in
            // value.entity is the tapped entity
            // value.location3D is the tap position in scene coordinates
        }
)
```

### Drag Gesture

```swift
.gesture(
    DragGesture()
        .targetedToEntity(entity)
        .onChanged { value in
            entity.position = value.convert(value.location3D, from: .local, to: entity.parent!)
        }
)
```

### Long Press

```swift
.gesture(
    LongPressGesture()
        .targetedToEntity(entity)
        .onEnded { _ in
            // Long press completed on entity
        }
)
```

### Gesture Conflicts with Hover

Drag gestures suppress hover effects during the drag. This is expected behavior. The hover highlight disappears when the user pinches and starts dragging, then reappears when released.

## Mixed SwiftUI + RealityKit Hierarchies

### Attachments (SwiftUI views in 3D space)

```swift
RealityView { content, attachments in
    if let panel = attachments.entity(for: "infoPanel") {
        panel.position = [0, 0.5, 0]
        content.add(panel)
    }
} attachments: {
    Attachment(id: "infoPanel") {
        VStack {
            Text("Item Details")
            Button("Select") { }  // Gets SwiftUI hover effect automatically
        }
        .padding()
        .glassBackgroundEffect()
    }
}
```

SwiftUI attachments use the SwiftUI hover system (`.hoverEffect()`), NOT `HoverEffectComponent`. They are two separate systems.

### Focus Coordination

- SwiftUI `@FocusState` controls keyboard focus for SwiftUI attachments
- RealityKit entities do not participate in `@FocusState` / `UIFocusEnvironment`
- Gaze hover works independently on both: SwiftUI views via `.hoverEffect()`, entities via `HoverEffectComponent`
- There is no API to programmatically move gaze hover (privacy by design)

## Volumes vs Immersive Spaces

### Volumes

- Fixed scale (do not resize with distance)
- Entities need all three components for interaction
- SwiftUI overlays use standard `.hoverEffect()`
- Bounded — content clipped to volume bounds

```swift
WindowGroup(id: "modelViewer") {
    RealityView { content in
        let model = try! await ModelEntity(named: "Trophy")
        model.components.set(InputTargetComponent())
        model.components.set(CollisionComponent(shapes: [.generateConvex(from: model.model!.mesh)]))
        model.components.set(HoverEffectComponent())
        content.add(model)
    }
}
.windowStyle(.volumetric)
```

### Immersive Spaces

- No system window chrome — all feedback must be explicit
- Same component requirements for entity interaction
- Hand tracking available for direct touch (no gaze needed)
- Spatial audio can provide hover feedback cues

```swift
ImmersiveSpace(id: "gallery") {
    RealityView { content in
        // Entities in immersive space
        // Must still have InputTargetComponent + CollisionComponent + HoverEffectComponent
    }
}
```

## Collision Shape Generation

### From Mesh (Most Accurate)

```swift
let shape = try await ShapeResource.generateConvex(from: entity.model!.mesh)
entity.components.set(CollisionComponent(shapes: [shape]))
```

Expensive for complex meshes. Use for final production entities.

### Primitives (Best Performance)

```swift
// Box
ShapeResource.generateBox(size: [width, height, depth])

// Sphere  
ShapeResource.generateSphere(radius: r)

// Capsule
ShapeResource.generateCapsule(height: h, radius: r)
```

Use primitives for performance-critical scenes with many entities.

### Compound Shapes

```swift
let head = ShapeResource.generateSphere(radius: 0.1)
    .offsetBy(translation: [0, 0.3, 0])
let body = ShapeResource.generateBox(size: [0.2, 0.4, 0.2])

entity.components.set(CollisionComponent(shapes: [head, body]))
```

## Performance Considerations

- **Collision complexity:** Convex hull generation is async and expensive. Pre-generate for known models.
- **Entity count:** Each entity with `HoverEffectComponent` is evaluated by the system compositor. Hundreds of hover-enabled entities can impact frame rate.
- **Shader effects:** Custom `ShaderGraphMaterial` hover effects run on GPU but add shader compilation overhead at load time.
- **InputTargetComponent scope:** Only add to entities that need interaction. Every `InputTargetComponent` adds to the input evaluation cost per frame.

## Common Mistakes

### 1. Collision shape not matching visual bounds
Gaze appears to miss the entity because the collision shape is too small or offset from the visual mesh.

### 2. Adding HoverEffectComponent to non-leaf entities
In a hierarchy, add hover effects to the specific child entities users should target, not to a parent group entity. Otherwise the entire group highlights as one.

### 3. Forgetting .generateConvex is async
`ShapeResource.generateConvex(from:)` is async. Calling it synchronously or forgetting to await causes crashes or missing collision shapes.

### 4. Not testing with eye tracking on device
The visionOS Simulator supports click-based interaction, not actual gaze. Hover timing, gaze accuracy, and eye fatigue effects only appear on real hardware.

### 5. Applying SwiftUI .hoverEffect() to RealityView
`.hoverEffect()` on the `RealityView` container highlights the entire view when gazed at, not individual entities. Use `HoverEffectComponent` on each entity instead.

### 6. Transparent materials blocking gaze
Entities with transparent materials still block gaze rays if they have `CollisionComponent`. Users cannot gaze through a transparent entity to reach one behind it unless the front entity has no collision.
