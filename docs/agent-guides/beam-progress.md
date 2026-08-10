# Beam Progress UI

Sorty's organization analysis screen uses the retained fallback beam renderer
for the visible progress surface in `Sources/SortyLib/Views/AnalysisView.swift`.
Do not mount `BorderBeamKit` in Sorty's scrolling or animated SwiftUI
hierarchies. Build 1540 demonstrated an AttributeGraph layout recursion through
its `TimelineView` and `GeometryReader` renderer.

Important implementation details:

- Keep the main progress surface as the medium rotating beam card with
  `RoundedRectangle(cornerRadius: 16)` and `referenceBeamFallback(...)`.
- Do not restore the old circular progress ring for the analysis screen.
- Do not add the small square elapsed-time pill below the card. It was removed
  because it was visually noisy and did not match the requested reference.
- The card uses `referenceBeamFallback(cornerRadius:active:)`. Keep this
  renderer lightweight and pause its decorative motion for Reduce Motion or
  inactive windows.
- If a fallback uses `TimelineView`, qualify it as `SwiftUI.TimelineView`;
  Sorty has its own `TimelineView` type for history, and an unqualified
  reference resolves to the wrong type.

If this UI needs further tuning, keep the fallback cheap. Avoid adding animated
blurred strokes, large drawing groups, or multiple timeline layers around this
card; they make the analysis screen lag during active organization.
