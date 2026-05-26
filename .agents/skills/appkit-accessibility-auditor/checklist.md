# AppKit Accessibility Checklist

This checklist is derived from Apple's official accessibility guidance and is intended for **manual verification** after applying changes suggested by the AppKit Accessibility Auditor.

Use VoiceOver and keyboard navigation as primary validation tools.

---

## VoiceOver Roles & Labels
- [ ] All actionable elements expose clear labels
- [ ] Labels match visible text where possible for predictable Voice Control commands
- [ ] Custom views expose appropriate accessibility roles
- [ ] Help text clarifies behavior where necessary
- [ ] No duplicated or confusing announcements

## Keyboard Navigation & Focus
- [ ] App is fully usable without a mouse
- [ ] Tab / Shift-Tab navigation reaches all interactive elements
- [ ] Focus order is predictable and logical
- [ ] No focus traps or dead ends
- [ ] Custom actions are reachable without pointer-only gestures

## Grouping & Reading Order
- [ ] Related content is grouped appropriately
- [ ] VoiceOver reading order matches the visual structure
- [ ] Dense layouts avoid excessive VoiceOver stops

## Tables & Outline Views
- [ ] Rows are understandable when read by VoiceOver
- [ ] Selection state is discoverable
- [ ] Column headers are accessible when present
- [ ] Custom cell views expose meaningful labels and values

## Custom Controls
- [ ] Custom controls behave like their native counterparts
- [ ] Controls are operable via keyboard (Space / Enter)
- [ ] Controls expose an accessibility press/action path where applicable
- [ ] State changes provide clear feedback

## Voice Control & Switch Control
- [ ] Voice Control can identify controls by clear, non-duplicated names
- [ ] Switch Control can reach interactive elements in a logical scan order
- [ ] Grouping reduces unnecessary scan stops without hiding actions

## Text & Scaling
- [ ] Text is readable at larger display or font scales
- [ ] Layout does not clip important content
- [ ] System fonts are preferred where possible

## Announcements & Updates
- [ ] Dynamic content updates are announced appropriately
- [ ] Announcements are meaningful and not excessive

## Color & Contrast
- [ ] States are not conveyed by color alone
- [ ] Icons, text, or VoiceOver cues reinforce state

---

## Final validation
- [ ] Screen is usable with VoiceOver enabled
- [ ] App is fully operable using keyboard only
- [ ] Non-pointer input remains usable where relevant
- [ ] No accessibility regressions introduced
