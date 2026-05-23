# SwiftUI Design Reference

Extended token definitions, component examples, and patterns.

## Color Extension Setup

Define all design tokens as a `Color` extension for project-wide access:

```swift
import SwiftUI

extension Color {
    static let appBackground = Color(hex: "F9F9F9")
    static let primaryText = Color(hex: "2D2D2D")
    static let secondaryText = Color(hex: "8E8E93")
    static let inputFill = Color(hex: "F5F5F5")

    // Category pastels — customize per project
    static let pastelPurple = Color(hex: "DCD6F7")
    static let pastelGreen = Color(hex: "E1EACD")
    static let pastelBlue = Color(hex: "C6E7FF")
    static let pastelOrange = Color(hex: "FFDDAE")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
```

## Full Component Examples

### Stats Card

A card displaying a metric with label:

```swift
VStack(alignment: .leading, spacing: 6) {
    Text("Total Hours")
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(Color.secondaryText)
    Text("128.5")
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .foregroundStyle(Color.primaryText)
}
.frame(maxWidth: .infinity, alignment: .leading)
.padding(16)
.background(Color.white)
.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
.shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
```

### List Row with Swipe Actions

```swift
HStack(spacing: 12) {
    Text("🎨")
        .font(.system(size: 22))
        .frame(width: 36, height: 36)
        .background(Color.pastelPurple.opacity(0.2))
        .clipShape(Circle())

    VStack(alignment: .leading, spacing: 2) {
        Text("Drawing Practice")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Color.primaryText)
        Text("45 min • Today")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(Color.secondaryText)
    }

    Spacer()
}
.padding(.vertical, 12)
.padding(.horizontal, 16)
.swipeActions(edge: .trailing, allowsFullSwipe: true) {
    Button(role: .destructive) {
        // delete
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
```

### Empty State

```swift
VStack(spacing: 16) {
    Image("EmptyStateIllustration")
        .resizable()
        .scaledToFit()
        .frame(height: 180)
        .accessibilityHidden(true)

    Text("No entries yet")
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .foregroundStyle(Color.primaryText)

    Text("Start tracking to see your progress here")
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .foregroundStyle(Color.secondaryText)
        .multilineTextAlignment(.center)
}
.padding(.horizontal, 40)
```

### Section with Collapsible Header

```swift
VStack(alignment: .leading, spacing: 12) {
    Button {
        withAnimation(.easeInOut(duration: 0.2)) {
            isCollapsed.toggle()
        }
    } label: {
        HStack {
            Text("Section Title")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primaryText)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
        }
    }
    .buttonStyle(.plain)

    if !isCollapsed {
        // Section content
    }
}
```

### Custom Tab Bar

```swift
HStack {
    ForEach(Tab.allCases, id: \.self) { tab in
        Button {
            selectedTab = tab
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selectedTab == tab ? Color.primaryText : Color.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
.frame(height: 56)
.background(
    Color.white
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -4)
)
```

### Celebration / Emoji Rain

For milestone moments — add a fun overlay:

```swift
struct EmojiRainOverlay: ViewModifier {
    let emoji: String
    @State private var particles: [(id: Int, x: CGFloat, delay: Double)] = []

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                ForEach(particles, id: \.id) { p in
                    Text(emoji)
                        .font(.system(size: 28))
                        .offset(x: p.x)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(
                            .linear(duration: 2.0).delay(p.delay),
                            value: particles.count
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }
}
```

## Do's and Don'ts

### Do
- Use `.continuous` corner radius style for Apple-native feel
- Define colors as static extensions, never inline hex
- Keep font declarations explicit (size + weight + `.rounded`)
- Use `Spacer()` sparingly — prefer explicit spacing values
- Add `.contentShape(Rectangle())` to make full rows tappable
- Use `.buttonStyle(.plain)` on custom button layouts

### Don't
- Use system semantic fonts (`.body`, `.title`) — they break consistency
- Use heavy shadows or colored shadows
- Mix rounded and non-rounded fonts
- Use borders on cards — rely on shadow + fill instead
- Over-animate — keep transitions under 0.4s
- Use pure black (`#000000`) — use `#2D2D2D` for text
- Forget `.accessibilityHidden(true)` on decorative images

## Adapting for Your Project

This design system is a starting point. To customize:

1. **Colors**: Swap the pastel palette to match your brand. Keep the same opacity rules.
2. **Typography**: Adjust the size scale if your content density differs. Keep `.rounded`.
3. **Spacing**: Scale uniformly if you need a denser or airier layout.
4. **Components**: Add project-specific components following the same shadow/radius/padding patterns.

The principles (minimal, friendly, clear hierarchy, consistent, delightful) stay constant — the tokens flex.
