import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Runtime hardware capabilities for the current machine.
public enum HardwareInfo {

    /// True when this process is running on Apple Silicon hardware.
    ///
    /// Uses a runtime `sysctl` probe instead of a compile-time `#if arch(arm64)`
    /// check so that a Rosetta-translated build is still reported correctly.
    public static var isAppleSilicon: Bool {
        #if canImport(Darwin)
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            return value == 1
        }
        #endif

        // Fallback for platforms without sysctl.
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// Marketing-style architecture name, useful for logs and diagnostics.
    public static var architecture: String {
        #if canImport(Darwin)
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            return value == 1 ? "arm64 (Apple Silicon)" : "x86_64 (Intel)"
        }
        #endif

        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
