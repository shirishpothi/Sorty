# Beam Progress UI

Sorty's organization analysis screen uses the Beam playground card shape for
the visible progress surface in `Sources/SortyLib/Views/AnalysisView.swift`.

Important implementation details:

- Keep the main progress surface as the Beam playground-style medium card:
  `RoundedRectangle(cornerRadius: 16)`, `Color(white: 0.08)`, `370x90`, and
  `.beam(.medium, palette: .colorful, theme: .dark, cornerRadius: 16)`.
- Do not restore the old circular progress ring for the analysis screen.
- Do not add the small square elapsed-time pill below the card. It was removed
  because it was visually noisy and did not match the requested reference.
- Sorty's `make now` path builds a manual SwiftPM app bundle. In that bundle,
  Beam's package shader resource lookup can fail silently, leaving the card
  with no visible border animation even though `.beam(...)` is present.
- BorderBeamKit also ships its shader as SwiftPM source. The manual app-bundle
  path must compile `BeamShaders.metal` into
  `Contents/Resources/BorderBeamKit_BorderBeamKit.bundle/default.metallib`.
  The vendored package explicitly prefers that embedded bundle because the
  generated `Bundle.module` accessor otherwise falls back to the raw build
  bundle, making SwiftUI display the shader layer's white source rectangle.
- For that reason, the card also has `referenceBeamFallback(cornerRadius:active:)`
  layered above the Beam modifier. This fallback is intentionally lightweight:
  one `SwiftUI.TimelineView`-driven 1px animated angular border, no blur/glow
  pass, no extra pill animation. The earlier blurred fallback was visibly laggy.
- Qualify this as `SwiftUI.TimelineView`; Sorty has its own `TimelineView`
  type for history, and an unqualified reference resolves to the wrong type.

If this UI needs further tuning, keep the fallback cheap. Avoid adding animated
blurred strokes, large drawing groups, or multiple timeline layers around this
card; they make the analysis screen lag during active organization.
