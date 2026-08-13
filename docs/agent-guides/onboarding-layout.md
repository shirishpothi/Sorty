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
Button beam fallbacks likewise use a retained conic gradient layer alongside
the Metal beam; do not add a second SwiftUI timeline for the same border.
Pause other timelines when their motion is not visible, prewarm file icons over
the intro reveal, and keep particle geometry deterministic across `body`
updates so view invalidation does not generate new animation targets.
