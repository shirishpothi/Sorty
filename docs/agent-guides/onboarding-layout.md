# Onboarding Layout

The onboarding window has a minimum content size of 1100 by 720 points. Its
main `VStack` owns the vertical allocation between the progress rail, step
content, and navigation controls. Non-completion steps receive the stack's
finite remaining size directly.

Do not wrap the whole step in a vertical `ScrollView`. Step roots use spacers
and flexible-height frames to fill the onboarding window; asking a scroll view
to find their unbounded ideal height creates a circular size dependency during
the intro-to-flow insertion and can trigger an AttributeGraph recursive-layout
abort. If one section needs overflow, keep its scroll view local and give it an
explicit finite height, as in the custom-persona list.

Animate presentation properties such as opacity and offset only after the flow
hierarchy has been inserted without animation. Do not animate insertion of the
scrolling layout itself.
