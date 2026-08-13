# Onboarding Layout

The onboarding window has a minimum content size of 1100 by 720 points. Its
main `VStack` owns the vertical allocation between the progress rail, step
content, and navigation controls. Non-completion steps receive the stack's
finite remaining size directly.

Do not wrap a whole step in a vertical `ScrollView`. Step roots use spacers and
flexible-height frames to fill the onboarding window; asking a scroll view to
find their unbounded ideal height creates a circular size dependency during the
intro-to-flow insertion and can trigger an AttributeGraph recursive-layout
abort. If one section needs overflow, keep its scroll view local and give it a
finite allocation from an explicit height or finite parent. The provider setup
pane reads its finite viewport and uses that as a local minimum content height,
which centers short configurations while allowing tall ones to scroll. The
custom-persona list uses an explicit height.

Prepare the flow hierarchy in a transaction with animations disabled, allow its
finite layout to resolve, and then animate presentation properties such as
opacity. Do not animate insertion of the step layout itself.

## Animation performance

Keep screen-sized effects out of SwiftUI frame timelines. The screen-edge glow
uses retained Core Animation gradient layers and pauses while Sorty is inactive;
do not replace it with a full-screen composited blur that redraws every frame.
The intro orbit keeps its native material-backed chips mounted and updates only
their layers from a display link. Its energy scan and the completion blob/ripple
motion likewise use retained layers; do not move those continuous effects back
into broad SwiftUI state or frame timelines. The full-window color climb is a
single asynchronous Canvas render pass; keep its gradient stops and blend mode
together rather than rebuilding multiple full-screen gradient subtrees during
every step transition.

An active beam uses one animated renderer. Button-sized pills use the retained
conic layer so several permission actions do not each create an independent
SwiftUI/Metal display clock. The large intro and completion calls to action use
the richer Metal renderer, with the retained conic layer only as their
static/inactive fallback. Never stack both animated renderers on one control.

Keep broad observable objects out of animated step roots. Permission and demo
adapters project only the status values their layouts consume, and the root
subscribes to `AppState` only at the completion destination. Provider input is
drafted locally and committed after typing settles so Keychain writes, model
refreshes, and connection tests do not compete with each keystroke. Pause other
motion when it is not visible, prewarm file icons over the intro reveal, and
keep particle geometry deterministic across `body` updates so invalidation does
not generate new animation targets.
