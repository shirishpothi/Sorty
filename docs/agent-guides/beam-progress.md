# Beam Progress UI

Sorty's organization analysis screen uses the native SwiftUI port of Jakub
Antalik's `border-beam` for the visible progress surface in
`Sources/SortyLib/Views/AnalysisView.swift`.

Important implementation details:

- Keep the main progress surface as the medium rotating beam card:
  `RoundedRectangle(cornerRadius: 16)` and
  `.borderBeam(.md, colorVariant: .colorful, theme: .dark, borderRadius: 16)`.
- Do not restore the old circular progress ring for the analysis screen.
- Do not add the small square elapsed-time pill below the card. It was removed
  because it was visually noisy and did not match the requested reference.
- Sorty's `make now` path builds a manual SwiftPM app bundle. In that bundle,
  package shader resource lookup can fail silently, leaving the card
  with no visible border animation even though `.beam(...)` is present.
- For that reason, the card also has `referenceBeamFallback(cornerRadius:active:)`
  layered above the border-beam modifier. This fallback is intentionally lightweight:
  one `SwiftUI.TimelineView`-driven 1px animated angular border, no blur/glow
  pass, no extra pill animation. The earlier blurred fallback was visibly laggy.
- Qualify this as `SwiftUI.TimelineView`; Sorty has its own `TimelineView`
  type for history, and an unqualified reference resolves to the wrong type.

If this UI needs further tuning, keep the fallback cheap. Avoid adding animated
blurred strokes, large drawing groups, or multiple timeline layers around this
card; they make the analysis screen lag during active organization.
