---
name: swiftui-design
description: Applies a minimal, friendly, and polished SwiftUI design philosophy when building iOS/macOS app interfaces. Use when creating new views, designing UI components, styling screens, or when the user asks for UI help, layout advice, or wants a beautiful SwiftUI interface.
---

# SwiftUI Design Philosophy

A design system rooted in **minimalism, friendliness, and clarity**. Apps built with this philosophy feel light, approachable, and polished — using soft colors, rounded typography, generous spacing, and subtle depth.

## Core Principles

1. **Minimal & Clean** — Remove visual noise. Every element earns its place.
2. **Friendly & Approachable** — Rounded fonts, emoji accents, and warm illustrations make the app feel human.
3. **Clear Hierarchy** — Size, weight, color, and spacing work together so users instantly see what matters.
4. **Consistent Patterns** — Reuse the same tokens, components, and rhythms everywhere.
5. **Delightful Details** — Subtle animations and celebratory moments reward engagement.

---

## Color System

### Philosophy
Light, airy backgrounds. Soft pastels for categorization. High contrast for text readability. Shadows and opacity for subtle depth — never heavy.

### Tokens

| Role | Value | Usage |
|------|-------|-------|
| Background | `#F9F9F9` | App-wide background |
| Surface | `#FFFFFF` | Cards, sheets, modals |
| Input Fill | `#F5F5F5` | Text fields, search bars |
| Primary Text | `#2D2D2D` | Headlines, body text |
| Secondary Text | `#8E8E93` | Captions, timestamps, hints |

### Category Accents (Pastel Palette)

Define 4-6 soft pastel accent colors for content categories. Examples:

| Category | Color | Hex |
|----------|-------|-----|
| Purple | Soft lavender | `#DCD6F7` |
| Green | Soft sage | `#E1EACD` |
| Blue | Soft sky | `#C6E7FF` |
| Orange | Soft peach | `#FFDDAE` |

Use category colors at low opacity (`0.1` to `0.3`) for backgrounds, and full strength only for small accents like dots or chips.

### Shadow & Depth

```swift
// Standard card shadow
.shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)

// Elevated element (floating buttons, popovers)
.shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)

// Subtle inner depth (optional stroke)
.overlay(
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.black.opacity(0.03), lineWidth: 1)
)
```

Keep shadow opacity between `0.03` and `0.08`. Never use dark or colored shadows.

---

## Typography

### Philosophy
Use **SF Rounded** (`.rounded` design) for warmth and friendliness. Build hierarchy through size and weight, not through color variety.

### Scale

| Level | Size | Weight | Usage |
|-------|------|--------|-------|
| Display | 34pt | Bold | Hero numbers, greetings |
| Title 1 | 24-28pt | Semibold/Bold | Page titles, section headers |
| Title 2 | 18-22pt | Bold | Card titles, feature names |
| Body | 16-17pt | Medium | Primary content, labels |
| Caption | 13-14pt | Medium/Semibold | Secondary info, metadata |
| Micro | 10-12pt | Bold | Badges, tiny labels |

### Pattern

```swift
// Always specify design: .rounded
.font(.system(size: 16, weight: .medium, design: .rounded))
```

Never use `.body`, `.title`, etc. system styles directly — always use explicit size + weight + `.rounded` for consistency across the app.

---

## Layout & Spacing

### Philosophy
Generous whitespace. Content breathes. Consistent rhythm using a spacing scale.

### Spacing Scale

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4pt | Tight gaps (icon-to-label) |
| sm | 8pt | Inline spacing |
| md | 12pt | Within components |
| lg | 16pt | Card padding, between elements |
| xl | 20-24pt | Section gaps, page padding |
| 2xl | 32pt | Major section separation |

### Page Layout

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 20) {
        // Content
    }
    .padding(.horizontal, 24)
    .padding(.top, 20)
    .padding(.bottom, 24)
}
.background(Color.appBackground)
```

### Alignment
- Text: `.leading` aligned (natural reading flow)
- Cards: Full-width with internal leading alignment
- Buttons: Centered text, full-width for primary actions
- Stats/numbers: Baseline-aligned when side by side

---

## Component Patterns

### Cards

The primary container. White background, rounded corners, subtle shadow.

```swift
VStack(alignment: .leading, spacing: 12) {
    // Card content
}
.padding(16)
.background(Color.white)
.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
.shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
```

Corner radius range: `16pt` to `24pt`. Use `.continuous` style for Apple-native feel.

### Buttons

**Primary** — Full-width, dark fill, white text:
```swift
Text("Save")
    .font(.system(size: 16, weight: .bold, design: .rounded))
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .background(Color.primaryText)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
```

**Icon button** — Circular, subtle shadow:
```swift
Image(systemName: "plus")
    .font(.system(size: 20, weight: .bold))
    .foregroundStyle(Color.primaryText)
    .frame(width: 44, height: 44)
    .background(Color.white)
    .clipShape(Circle())
    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
```

**Disabled state**: `Color.gray.opacity(0.3)` background, no interaction feedback.

### Input Fields

```swift
TextField("Placeholder", text: $value)
    .font(.system(size: 16, weight: .medium, design: .rounded))
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color.inputFill) // #F5F5F5
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
```

No visible borders. Rely on fill color to define the field. Use `16pt` corner radius.

### Sheets

```swift
.sheet(isPresented: $showSheet) {
    SheetContent()
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
}
```

Sheet content uses the same `24pt` horizontal padding. White background. Always show drag indicator.

### Category Chips

Small rounded pills for filtering/selection:
```swift
Text(category.name)
    .font(.system(size: 13, weight: .semibold, design: .rounded))
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(isSelected ? categoryColor.opacity(0.25) : Color.gray.opacity(0.08))
    .clipShape(Capsule())
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
```

---

## Navigation

### Custom Tab Bar

Build a custom tab bar instead of using SwiftUI's `TabView` for full design control:
- Height: `56pt`
- White background with top shadow
- Icons: `22pt` semibold SF Symbols
- Active: Primary text color. Inactive: Secondary text color.
- No labels — icons only for a cleaner look (or small labels if needed).

### Navigation Headers

- Title: `18pt` bold rounded, centered
- Back button: Chevron-left in a `44pt` circular white button
- Action buttons: Same circular style, positioned trailing

---

## Animation

### Philosophy
Animations are **subtle and purposeful**. They guide attention, not distract.

### Patterns

| Type | Duration | Curve | Usage |
|------|----------|-------|-------|
| State toggle | 0.2s | `.easeInOut` | Expand/collapse, show/hide |
| Interactive | 0.3s | `.spring(response: 0.3, dampingFraction: 0.7)` | Selection, chip press |
| Celebration | Variable | `.linear` | Confetti, emoji rain |

```swift
// State changes
withAnimation(.easeInOut(duration: 0.2)) {
    isExpanded.toggle()
}

// Interactive feedback
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
```

Never animate without purpose. Keep durations under 0.4s for UI state changes.

---

## Icons & Personality

### SF Symbols
- Weight: `.semibold` to `.bold`
- Size: `14pt` to `22pt` depending on context
- Color: `primaryText` or `secondaryText`

### Emoji
Use emoji as visual accents for personality (not decoration):
- Display in circular containers with category-colored backgrounds
- Size: `22pt` to `30pt`
- Container: `36pt` to `70pt` circle with `categoryColor.opacity(0.15)`

### Illustrations
Use custom illustrations for empty states and celebrations — they add warmth. Hide from accessibility with `.accessibilityHidden(true)`.

---

## Visual Hierarchy Checklist

When building any screen, verify:

- [ ] **One focal point** — The most important element is clearly the largest/boldest
- [ ] **Max 3 text sizes** per card — Display, body, caption
- [ ] **Consistent spacing rhythm** — Use the spacing scale, don't improvise
- [ ] **Cards group related content** — Don't scatter related info
- [ ] **Secondary info is truly secondary** — Smaller, lighter, less prominent
- [ ] **Whitespace is generous** — When in doubt, add more space
- [ ] **Touch targets >= 44pt** — All interactive elements are easily tappable

---

## Quick Reference: Token Summary

```
Colors:     Background #F9F9F9  |  Surface #FFFFFF  |  Input #F5F5F5
            Primary Text #2D2D2D  |  Secondary Text #8E8E93

Font:       Always .design(.rounded)
            Display 34pt bold  |  Title 24pt semi  |  Body 16pt med  |  Caption 13pt med

Spacing:    Page H-pad 24pt  |  Card pad 16pt  |  Section gap 20-32pt

Radius:     Cards 16-24pt (.continuous)  |  Inputs 16pt  |  Buttons 16pt  |  Chips Capsule

Shadows:    Cards 0.04/8/0/4  |  Elevated 0.08/12/0/6

Animation:  State 0.2s easeInOut  |  Interactive 0.3s spring
```

## Additional Resources

- For full token definitions and extended examples, see [reference.md](reference.md)
