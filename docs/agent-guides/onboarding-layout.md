# Onboarding Layout

The onboarding window has a minimum content size of 1100 by 720 points. Its
main `VStack` owns the vertical allocation between the progress rail, step
content, and navigation controls.

For non-completion steps, keep the vertical `ScrollView` free of
`maxHeight: .infinity`, and do not put a `maxWidth: .infinity` flexible frame
directly around its step content. The stack proposes the remaining height and
the scroll view uses `layoutPriority(1)`. Making the scroll view and its child
both fill all available space creates a circular ideal-size dependency during
the intro-to-flow insertion and can trigger an AttributeGraph recursive-layout
abort.

Animate presentation properties such as opacity and offset only after the flow
hierarchy has been inserted without animation. Do not animate insertion of the
scrolling layout itself.
