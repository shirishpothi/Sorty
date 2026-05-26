# UIKit Accessibility Checklist

This checklist is derived from Apple's official accessibility guidance and is intended for **manual verification** after applying changes suggested by the UIKit Accessibility Auditor.

Use VoiceOver, Dynamic Type, and touch interaction to validate behavior.

---

## VoiceOver Labels & Values
- [ ] All actionable elements have meaningful accessibility labels
- [ ] Labels match visible text where possible for predictable Voice Control commands
- [ ] Icon-only buttons are understandable without visual context
- [ ] Changing states expose updated accessibility values
- [ ] Hints are used only when they add meaningful guidance

## Traits & Roles
- [ ] Correct traits are applied (button, header, selected, disabled)
- [ ] Custom controls expose appropriate roles and states

## Reading Order & Grouping
- [ ] VoiceOver navigation order is logical
- [ ] Complex cells are grouped appropriately
- [ ] No unnecessary VoiceOver stops inside a single cell

## Dynamic Type
- [ ] Text scales with the user's preferred content size category
- [ ] Custom fonts scale using UIFontMetrics
- [ ] Layout supports large text without clipping important content

## Touch Targets & Interaction
- [ ] Tap targets are large enough for comfortable interaction
- [ ] Custom hit areas respond consistently
- [ ] Interactive elements are discoverable via VoiceOver
- [ ] Custom gesture-driven controls expose an accessible activation path

## Voice Control, Switch Control & Keyboard
- [ ] Voice Control "Show names" exposes clear, non-duplicated labels
- [ ] Switch Control can reach controls in a logical scan order
- [ ] Full Keyboard Access can focus and activate interactive elements
- [ ] Secondary actions are exposed through custom actions when hidden behind gestures

## Screen Changes & Announcements
- [ ] Screen transitions are announced when appropriate
- [ ] Dynamic content updates are communicated clearly
- [ ] Announcements are not overused

## Color & State
- [ ] States are not conveyed by color alone
- [ ] Error/success/selection states are understandable via VoiceOver

---

## Final validation
- [ ] Screen is usable with VoiceOver enabled
- [ ] Screen works at extreme Dynamic Type sizes
- [ ] Screen remains operable with non-touch input where relevant
- [ ] No accessibility regressions introduced
