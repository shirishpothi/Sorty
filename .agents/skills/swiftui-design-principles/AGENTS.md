# SwiftUI Design Principles

This repository contains an agent skill for building polished SwiftUI apps and WidgetKit widgets.

## Structure

- `SKILL.md` — The skill definition with all design principles
- `metadata.json` — Skill metadata (version, author, abstract)
- `LICENSE` — MIT license

## How the skill works

The skill is loaded when an agent detects SwiftUI or WidgetKit-related tasks. It provides:

1. A base-4/8 spacing grid to prevent arbitrary padding values
2. A typography hierarchy using weight differentiation (not just size)
3. System semantic color usage instead of hardcoded opacity values
4. Native WidgetKit patterns (Gauge, containerBackground)
5. A pre-ship checklist for verification

The skill is purely instructional — no scripts or build steps required.
