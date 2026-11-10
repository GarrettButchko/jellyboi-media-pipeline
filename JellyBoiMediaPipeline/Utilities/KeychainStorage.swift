import SwiftUI

/// A property wrapper type that reflects a value stored securely in the system Keychain
/// and invalidates a SwiftUI view when the value changes, behaving like `@AppStorage` but with hardware-backed encryption.
@propertyWrapper
public struct KeychainStorage: DynamicProperty {
    @State private var value: String
    private let key: String
    private let service: String

    public var wrappedValue: String {
        get { value }
        nonmutating set {
            value = newValue
            KeychainHelper.shared.set(newValue, forKey: key, service: service)
        }
    }

    public var projectedValue: Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }

    public init(wrappedValue defaultValue: String = "", _ key: String, service: String = KeychainHelper.defaultService) {
        self.key = key
        self.service = service
        let stored = KeychainHelper.shared.get(forKey: key, service: service) ?? defaultValue
        self._value = State(initialValue: stored)
    }
}
