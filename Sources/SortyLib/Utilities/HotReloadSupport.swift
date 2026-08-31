import Inject
import SwiftUI

/// Invalidates a SwiftUI value when InjectionNext loads an updated implementation.
/// Inject compiles this observer to a no-op outside Debug builds.
@propertyWrapper @MainActor
public struct SortyHotReload: DynamicProperty {
    public struct Observation: Sendable {
        fileprivate init() {}
    }

    @Inject.ObserveInjection private var injection

    public nonisolated init() {}

    public var wrappedValue: Observation {
        _ = injection
        return Observation()
    }
}
