# Contributing to Swift FocusEngine Pro

Contributions are welcome! This skill helps AI coding assistants write correct focus management code for Apple platforms.

## What to Contribute

- **Edge cases** — non-obvious focus behaviors that catch developers off guard
- **New platform APIs** — iOS 19, tvOS 19, visionOS 3, watchOS 12 additions
- **Real-world patterns** — battle-tested solutions from production apps
- **Anti-patterns** — mistakes LLMs commonly generate

## Guidelines

- Keep reference files focused and under 300 lines each
- Don't repeat things LLMs already know — focus on what they get wrong
- Include code examples that compile and demonstrate the concept
- Note minimum OS version requirements for every API mentioned
- All contributions must be MIT licensed

## Structure

Reference files live in `swift-focusengine-pro/references/`. Each file covers a specific topic:

| File | Focus |
|------|-------|
| `anti-patterns.md` | Critical mistakes that break focus |
| `swiftui-focus.md` | tvOS SwiftUI focus APIs |
| `uikit-focus.md` | tvOS UIKit focus APIs |
| `ios-focus.md` | iOS/iPadOS focus (keyboard, game controller, Stage Manager) |
| `watchos-focus.md` | watchOS Digital Crown and sequential focus |
| `visionos-focus.md` | visionOS gaze, hover, and focus |
| `realitykit-focus.md` | RealityKit entity hover and gestures |
| `focus-styling.md` | Focus visual styling patterns |
| `focus-restoration.md` | Focus state preservation across data reloads |
| `layout-patterns.md` | Common tvOS layout patterns |
| `async-focus.md` | Async/await and focus coordination |
| `accessibility-focus.md` | VoiceOver, Full Keyboard Access, Switch Control |
| `debugging.md` | Focus debugging tools and techniques |

## Submitting Changes

1. Fork the repo
2. Create a branch (`git checkout -b my-improvement`)
3. Make your changes
4. Test that examples compile and are accurate
5. Submit a pull request with a clear description of what you added and why

## Code of Conduct

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) before contributing.
