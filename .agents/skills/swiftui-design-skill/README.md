# SwiftUI Design Skill

A [Cursor AI](https://cursor.com) agent skill that applies a minimal, friendly, and polished SwiftUI design philosophy when building iOS/macOS app interfaces.

## What It Does

When you ask Cursor to create views, design components, or style screens, this skill automatically guides it to follow a cohesive design system rooted in:

- **Minimalism** — Clean, uncluttered interfaces where every element earns its place
- **Friendliness** — SF Rounded typography, emoji accents, and warm illustrations
- **Clear Hierarchy** — Size, weight, color, and spacing work together
- **Consistency** — Reusable tokens and patterns throughout
- **Delight** — Subtle animations and celebratory moments

## Design Highlights

| Aspect | Approach |
|--------|----------|
| Colors | Light backgrounds, soft pastels for categories, subtle shadows |
| Typography | SF Rounded, explicit size/weight scale (no system semantic fonts) |
| Layout | Generous whitespace, 6-tier spacing scale |
| Components | Cards, buttons, inputs, sheets, chips — all with code patterns |
| Animation | Purposeful, short (0.2–0.3s), spring for interactive elements |
| Personality | SF Symbols + emoji + custom illustrations |

## Installation

### Option 1: Clone to personal skills (available across all projects)

```bash
git clone https://github.com/harperhhh/swiftui-design-skill.git ~/.cursor/skills/swiftui-design
```

### Option 2: Add to a specific project (shared via repo)

```bash
git clone https://github.com/harperhhh/swiftui-design-skill.git .cursor/skills/swiftui-design
```

Or copy the `SKILL.md` and `reference.md` files manually into the appropriate `skills/swiftui-design/` directory.

## Files

| File | Description |
|------|-------------|
| `SKILL.md` | Core design philosophy, tokens, and component patterns |
| `reference.md` | Extended examples, Color extension setup, do's and don'ts |

## Usage

Once installed, the skill activates automatically whenever you ask Cursor to help with SwiftUI UI work — creating views, designing components, styling screens, or building layouts.

It won't force an identical design on every app. Instead, it teaches the agent the *principles* — your apps will share the same quality and feel while looking unique.

## License

MIT
