import Inject

/// Invalidates a SwiftUI value when InjectionNext loads an updated implementation.
/// Inject compiles this observer to a no-op outside Debug builds.
public typealias SortyHotReload = Inject.ObserveInjection
