# Onboarding Layout

The onboarding window has a minimum content size of 1100 by 720 points. Its
main `VStack` owns the vertical allocation between the progress rail, step
content, and navigation controls. Non-completion steps receive the stack's
finite remaining size directly.

The completion step uses 16-point vertical spacing within that finite
allocation. Keep it centered without extra vertical padding or a fixed offset
so the final action remains fully inside the window at its minimum height.

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

Drive each entrance state from one animation boundary. Set `hasAppeared`
directly when its panes already have value-scoped spring modifiers; wrapping
that same mutation in `withAnimation` creates a second broad transaction and
can animate unrelated work during the first render. Gate those local springs
with Reduce Motion. The completion sequence follows this rule too: its
checkmark, copy, tips, and CTA own their staggered springs, while retained glow
and particle layers own their motion, so their trigger states are assigned
directly rather than wrapped in another animation transaction.

## Animation performance

Keep screen-sized effects out of onboarding entirely. Do not place dimming,
glow, blur, material, or other translucent panels across a monitor behind the
onboarding window: windows underneath update as the cursor moves, forcing
WindowServer to recompose that monitor-sized stack and starving the orbit's
compositor frames even while Sorty's main thread is idle.
The window-edge glow is the narrow exception: keep its auxiliary surface bounded
to a small outset around the onboarding frame, attach it below the parent window,
ignore mouse events, and animate retained Core Animation opacity and shadow blur.
Reduce Motion must leave a static glow rather than running the pulse.
Retained-effect adapters also guard identical visibility, motion, and activity
inputs; their stopped state is idempotent, so unrelated SwiftUI updates do not
re-remove animations or rewrite layer opacity and phase.
Cache invariant retained-layer palettes at construction and only rebuild
variant-specific colors when the variant changes.
The intro orbit keeps its original material-backed SwiftUI chips mounted. Its
idle sine components run as additive Core Animation keyframes. Each finished
chip is rasterized at the window's native backing scale, preserving its material
appearance while pointer-event processing moves one cached compositor surface
per file. The full-window AppKit container returns `nil` from `hitTest` so
pointer movement never traverses the decorative card subtree, and identical
representable inputs must not rewrite the chips' base layers.
Pause the orbit while Sorty is inactive, preserving its phase for a clean
resume; moving the pointer to another display without deactivating Sorty must
not affect it. Its Gaussian glow and energy
scan, plus the completion blob, ripple, and particle motion, likewise use
retained layers; do not move those continuous effects back into broad SwiftUI
state or frame timelines. The completion reveal rasterizes its large blurred
artwork once and animates retained scale and opacity through the same two phases;
Reduce Motion keeps the reveal as a short opacity fade. The optional demo's
continuous organizing sliver follows the same rule, and its per-file/folder
collections are derived once per mutation rather
than repeatedly filtered in row builders. The full-window color climb uses
retained accent, shade, and additive radial-gradient layers. Step changes
animate only their colors and geometry; do not restore a full-window SwiftUI
Canvas or multiple gradient subtrees that redraw throughout every transition.
When Sorty becomes inactive, completion glow and ripple layers pause their
existing layer time and resume from the same phase instead of rebuilding their
infinite animation groups.
Completion copy, tips, checkmark, analytics, and CTA entrance springs are also
disabled under Reduce Motion; their fully revealed state remains unchanged.
The intro's one-shot energy sweep uses Core Animation completion and pauses its
layer clock while inactive, so it never restarts its delay or keyframes merely
because focus moved to another app.
The intro CTA changes the orbit's collapse target only when hover enters or
exits. Resolve the button center inside the intro's local coordinate space;
never measure global pointer geometry or publish per-mouse-move state. Hover
must not invalidate the reveal or audio root. Keep this CTA's system glass
noninteractive: its explicit hover state owns the collapse interaction, while
interactive glass would independently track every pointer move.

An active beam uses one animated renderer. Button-sized pills use the retained
conic layer so several permission actions do not each create an independent
SwiftUI/Metal display clock. The intro CTA uses this same retained onboarding
beam; the large completion call to action uses the richer Metal renderer, with
the retained conic layer only as its static/inactive fallback. Never stack both
animated renderers on one control.
Retained button beams pause their conic layer clocks while the window is
inactive and resume at the same phase; they only reset to the static fallback
when animation is actually disabled or Reduce Motion is enabled.
The optional CTA interior glow keeps its radial glow and blur tree static and
rotates only a retained Core Animation conic mask; do not restore its 30 fps
SwiftUI timeline.
Prewarm completion audio and its reveal accent before reaching the completion
step; map the bundled audio data off the main actor so constructing an
`AVAudioPlayer` or resolving `NSSound` does not compete with celebration frames.
The intro similarly maps its bundled soundtrack data
off the main actor during the opening beat, then starts playback at the original
cue; do not move that file read back onto the icon-reveal frame.

Keep broad observable objects out of animated step roots. Permission and demo
adapters project only the status values their layouts consume, and the root
subscribes to `AppState` only at the completion destination. The provider step
owns the single value-semantic readiness calculation and passes only a distinct
setup status to the root; do not add a second root auth/settings observer. The
completion celebration resolves service references without observing their
other state, and seeds its analytics preference when the view is created rather
than publishing a corrective state update on its first frame. Provider input is
drafted locally and committed
after typing settles so Keychain writes, model refreshes, and connection tests
do not compete with each keystroke. The provider grid is an Equatable leaf keyed
only by the selected provider, so draft/status changes do not rebuild its glass
cards and cached logos. Provider readiness is resolved from an Equatable input
snapshot off the main actor; never query Keychain from a view body or navigation
render pass. Pause other motion when it is not visible,
prewarm file icons over the intro reveal, and keep particle geometry
deterministic across `body` updates so invalidation does not generate new
animation targets.

Treat provider selection and authentication as single-flight work. A provider
change already normalizes its URL, credential requirement, and default model in
`SettingsViewModel`; onboarding must not repeat those mutations. Concurrent
Codex status requests share one CLI probe, and manual verification awaits that
resolved state before updating its button. Executable discovery, status checks,
and auth-file parsing stay inside that single background probe. The provider
step observes the Codex manager it renders directly; do not also subscribe its
entire layout to the subscription-auth mirror merely to trigger refresh
methods. Model refreshes
cancel superseded presentation tasks and apply results only when their captured
provider is still selected, preventing rapid selection changes from publishing
stale model lists. The onboarding-specific Copilot catalog request is likewise
single-flight and is cancelled when the provider pane disappears or selection
moves away from Copilot.

GitHub Copilot authentication follows the same distinct-state rule: cancelled
status checks stop before publishing, profile refresh stays inside the single
coalesced check, and terminal device-flow errors end polling. Never keep
publishing the same error or auth fields into the provider step after polling
has already failed.

Keep scheduling and event bookkeeping out of SwiftUI state. Trackpad swipe
deltas, cancellable task handles, service references used only by actions, and
queued demo work items live in stable non-observable controllers; mutating them
must not invalidate an active step. Permission refreshes coalesce duplicate
requests, enumerate protected locations off the main actor, and publish one
permission-state snapshot instead of redrawing the full step once per row.
The workflow step renders only persisted custom personas. Never inject stress
fixtures in `CustomPersonaStore` initialization: that materializes large
glass-card collections throughout the real app, including onboarding.
Persona selection springs belong to the cards whose selection state changes;
do not wrap shared-manager or generator-presentation mutations in a broad
workflow animation transaction. Selection managers guard identical values, and
publish and persist only the selection fields that actually change; callers
must not repeat state normalization the manager already performs.

Use interactive Liquid Glass only for controls. Permission rows keep native
regular glass but leave pointer-responsive glass to their contained buttons;
the row's own hover, shadow, and context-menu behavior remain SwiftUI-driven.
Permission action frame probes measure only during AppKit layout or actual
window geometry notifications, coalesce same-runloop reports, and treat normal
SwiftUI representable updates as bookkeeping rather than another measurement.
The resolved-manager callback owns the initial permission refresh; do not also
launch an identical parent `onAppear` refresh before those managers arrive.
If another lifecycle event requests permission state while a refresh is in
flight, coalesce it into one follow-up pass instead of overlapping system probes.
Delay provider CLI/auth/model preflight until the initial pane reveal has
settled, and only probe Apple model availability when that provider is active.
Keep hover-only connection-button state in its button leaf; provider changes
and connection-result transitions animate their right-pane/status subtrees,
not the entire two-pane provider step.
Account privacy reveals and Codex action-button hover state follow the same leaf
ownership rule, so pointer movement never invalidates the provider root.
Likewise, a permission video representable must treat an unchanged URL/player
pair as a no-op; ordinary SwiftUI updates must not restart an already-playing
queue. Pause permission video playback while Sorty is deactivated, then resume
its retained instance when the app becomes active.
