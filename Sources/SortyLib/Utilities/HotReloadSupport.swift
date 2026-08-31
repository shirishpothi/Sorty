import Foundation
import SwiftUI
import Combine

#if DEBUG
private final class SortyInjectionObserver: ObservableObject, @unchecked Sendable {
    static let shared = SortyInjectionObserver()

    let objectWillChange = ObservableObjectPublisher()
    private var injectionSubscription: AnyCancellable?

    private init() {
        loadInjectionBundle()
        injectionSubscription = NotificationCenter.default
            .publisher(for: Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    private func loadInjectionBundle() {
        guard NSClassFromString("InjectionClient") == nil else { return }

        let path = "/Applications/InjectionNext.app/Contents/Resources/macOSInjection.bundle"
        guard let bundle = Bundle(path: path), bundle.load() else {
            print("Hot reload unavailable: InjectionNext is not installed in /Applications.")
            return
        }
    }
}
#endif

/// Invalidates a SwiftUI value when InjectionNext loads an updated implementation.
/// Release builds retain only this wrapper's inert value.
@propertyWrapper @MainActor
public struct SortyHotReload: DynamicProperty {
    public struct Observation: Sendable {
        fileprivate init() {}
    }

#if DEBUG
    @ObservedObject private var observer = SortyInjectionObserver.shared
#endif

    public init() {}

    public var wrappedValue: Observation {
#if DEBUG
        _ = observer
#endif
        return Observation()
    }
}
