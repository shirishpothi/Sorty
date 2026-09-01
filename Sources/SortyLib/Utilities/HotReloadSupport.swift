import Foundation
import Combine
import SwiftUI

#if DEBUG && SORTY_HOT_RELOAD
import InjectionLite

@MainActor
private final class SortyInjectionObserver: @MainActor ObservableObject {
    static let shared = SortyInjectionObserver()

    let objectWillChange = ObservableObjectPublisher()
    private var injectionSubscription: AnyCancellable?

    private init() {
        injectionSubscription = NotificationCenter.default
            .publisher(for: Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }
}
#endif

/// Invalidates a SwiftUI value when InjectionLite loads an updated implementation.
/// Normal Debug and Release builds retain only this wrapper's inert value.
@propertyWrapper @MainActor
public struct SortyHotReload: DynamicProperty {
    public struct Observation: Sendable {
        fileprivate init() {}
    }

#if DEBUG && SORTY_HOT_RELOAD
    @ObservedObject private var observer = SortyInjectionObserver.shared
#endif

    public init() {}

    public var wrappedValue: Observation {
#if DEBUG && SORTY_HOT_RELOAD
        _ = observer
#endif
        return Observation()
    }
}
