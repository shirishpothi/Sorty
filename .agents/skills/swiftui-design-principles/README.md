# SwiftUI Design Principles

An agent skill that encodes design principles for building polished, native-feeling SwiftUI apps and WidgetKit widgets.

Derived from a side-by-side comparison of two iOS apps built with AI coding tools — one that looked and felt polished, and one where the margins, spacing, text sizes, and widgets were just *off*. The patterns here represent the concrete differences between the two.

## Install

```bash
npx skills add arjitj2/swiftui-design-principles
```

## What it covers

| # | Principle | What it prevents |
|---|-----------|-----------------|
| 1 | Spacing system (base-4/8 grid) | Arbitrary padding values like 26, 34, 36pt |
| 2 | Typography hierarchy (weight-based) | 7+ font sizes with no clear system |
| 3 | System semantic colors | Hardcoded `Color.white.opacity(0.42)` everywhere |
| 4 | Proportional component sizing | 260pt progress rings, mismatched stroke widths |
| 5 | Native grouped content | Over-engineered gradient cards with 22pt corners |
| 6 | NavigationStack usage | Bare ZStack layouts with manual titles |
| 7 | WidgetKit native components | Manual circle drawing instead of Gauge |
| 8 | Interactive elements | Hidden Toggle labels, low-contrast tints |
| 9 | Shared data models | Duplicated logic between app and widget |
| 10 | Pre-ship checklist | Quick verification before shipping |

## When it activates

The skill triggers when creating or modifying:
- SwiftUI views
- iOS widgets (WidgetKit)
- Any native Apple UI

## Compatible agents

Works with Claude Code, Cursor, Cline, GitHub Copilot, Windsurf, and any agent that supports the [Agent Skills](https://skills.sh) format.

## License

MIT
