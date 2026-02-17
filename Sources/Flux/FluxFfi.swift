import Foundation

// MARK: - C Function Declarations

// These are the C functions exported by the Flux native library.
// They are loaded dynamically at runtime.

/// Function pointer types for Flux FFI
private typealias FluxWhoopToHsiDailyFunc = @convention(c) (
    UnsafePointer<CChar>,  // json
    UnsafePointer<CChar>,  // timezone
    UnsafePointer<CChar>   // device_id
) -> UnsafeMutablePointer<CChar>?

private typealias FluxGarminToHsiDailyFunc = @convention(c) (
    UnsafePointer<CChar>,  // json
    UnsafePointer<CChar>,  // timezone
    UnsafePointer<CChar>   // device_id
) -> UnsafeMutablePointer<CChar>?

private typealias FluxProcessorNewFunc = @convention(c) (Int32) -> UnsafeMutableRawPointer?
private typealias FluxProcessorFreeFunc = @convention(c) (UnsafeMutableRawPointer?) -> Void

private typealias FluxProcessorProcessWhoopFunc = @convention(c) (
    UnsafeMutableRawPointer?,  // processor
    UnsafePointer<CChar>,      // json
    UnsafePointer<CChar>,      // timezone
    UnsafePointer<CChar>       // device_id
) -> UnsafeMutablePointer<CChar>?

private typealias FluxProcessorProcessGarminFunc = @convention(c) (
    UnsafeMutableRawPointer?,  // processor
    UnsafePointer<CChar>,      // json
    UnsafePointer<CChar>,      // timezone
    UnsafePointer<CChar>       // device_id
) -> UnsafeMutablePointer<CChar>?

private typealias FluxProcessorSaveBaselinesFunc = @convention(c) (
    UnsafeMutableRawPointer?   // processor
) -> UnsafeMutablePointer<CChar>?

private typealias FluxProcessorLoadBaselinesFunc = @convention(c) (
    UnsafeMutableRawPointer?,  // processor
    UnsafePointer<CChar>       // json
) -> Int32

private typealias FluxFreeStringFunc = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
private typealias FluxLastErrorFunc = @convention(c) () -> UnsafePointer<CChar>?

// MARK: - FluxFfi

/// FFI bindings for Synheart Flux native library
///
/// This class provides access to the Rust Flux library via C FFI.
/// If the native library is not available, all methods return nil
/// (graceful degradation).
public final class FluxFfi {

    /// Shared singleton instance
    public static let shared = FluxFfi()

    private var libraryHandle: UnsafeMutableRawPointer?
    private var loadAttempted = false
    private var _loadError: String?

    // Function pointers
    private var whoopToHsiDaily: FluxWhoopToHsiDailyFunc?
    private var garminToHsiDaily: FluxGarminToHsiDailyFunc?
    private var processorNew: FluxProcessorNewFunc?
    private var processorFree: FluxProcessorFreeFunc?
    private var processorProcessWhoop: FluxProcessorProcessWhoopFunc?
    private var processorProcessGarmin: FluxProcessorProcessGarminFunc?
    private var processorSaveBaselines: FluxProcessorSaveBaselinesFunc?
    private var processorLoadBaselines: FluxProcessorLoadBaselinesFunc?
    private var freeString: FluxFreeStringFunc?
    private var lastError: FluxLastErrorFunc?

    private init() {}

    /// Check if the native Flux library is available
    public var isAvailable: Bool {
        ensureLoadAttempted()
        return libraryHandle != nil
    }

    /// Get the error message if the library failed to load
    public var loadError: String? {
        ensureLoadAttempted()
        return _loadError
    }

    /// Reset load state for testing
    public func resetForTesting() {
        if let handle = libraryHandle {
            dlclose(handle)
        }
        libraryHandle = nil
        loadAttempted = false
        _loadError = nil
        whoopToHsiDaily = nil
        garminToHsiDaily = nil
        processorNew = nil
        processorFree = nil
        processorProcessWhoop = nil
        processorProcessGarmin = nil
        processorSaveBaselines = nil
        processorLoadBaselines = nil
        freeString = nil
        lastError = nil
    }

    private func ensureLoadAttempted() {
        guard !loadAttempted else { return }
        loadAttempted = true

        // Try to load the library
        let libraryName = "libsynheart_flux"

        // Try different paths
        let paths = [
            // Bundled in app framework
            Bundle.main.privateFrameworksPath.map { "\($0)/\(libraryName).dylib" },
            // In app bundle resources
            Bundle.main.path(forResource: libraryName, ofType: "dylib"),
            // XCFramework path (iOS)
            Bundle.main.path(forResource: "SynheartFlux", ofType: "framework").map { "\($0)/SynheartFlux" },
            // Direct in bundle
            Bundle.main.bundlePath + "/\(libraryName).dylib",
            // System path (for testing)
            "/usr/local/lib/\(libraryName).dylib"
        ].compactMap { $0 }

        var loadedHandle: UnsafeMutableRawPointer?
        var errors: [String] = []

        for path in paths {
            if let handle = dlopen(path, RTLD_NOW) {
                loadedHandle = handle
                break
            } else if let error = dlerror() {
                errors.append("\(path): \(String(cString: error))")
            }
        }

        // Also try loading from linked framework (symbols in process)
        if loadedHandle == nil {
            loadedHandle = dlopen(nil, RTLD_NOW)
            if loadedHandle != nil {
                // Check if flux symbols are available
                if dlsym(loadedHandle, "flux_whoop_to_hsi_daily") == nil {
                    dlclose(loadedHandle!)
                    loadedHandle = nil
                }
            }
        }

        guard let handle = loadedHandle else {
            _loadError = "Failed to load Flux native library. Tried paths: \(errors.joined(separator: "; "))"
            print("[FluxFfi] \(_loadError!)")
            return
        }

        libraryHandle = handle

        // Load function pointers
        whoopToHsiDaily = loadFunction(handle, "flux_whoop_to_hsi_daily")
        garminToHsiDaily = loadFunction(handle, "flux_garmin_to_hsi_daily")
        processorNew = loadFunction(handle, "flux_processor_new")
        processorFree = loadFunction(handle, "flux_processor_free")
        processorProcessWhoop = loadFunction(handle, "flux_processor_process_whoop")
        processorProcessGarmin = loadFunction(handle, "flux_processor_process_garmin")
        processorSaveBaselines = loadFunction(handle, "flux_processor_save_baselines")
        processorLoadBaselines = loadFunction(handle, "flux_processor_load_baselines")
        freeString = loadFunction(handle, "flux_free_string")
        lastError = loadFunction(handle, "flux_last_error")

        print("[FluxFfi] Successfully loaded native library")
    }

    private func loadFunction<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let sym = dlsym(handle, name) else {
            print("[FluxFfi] Warning: Could not find symbol '\(name)'")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }

    // MARK: - Public API

    /// Process WHOOP JSON and return HSI JSON (stateless)
    ///
    /// - Parameters:
    ///   - json: Raw WHOOP API response JSON
    ///   - timezone: User's timezone (e.g., "America/New_York")
    ///   - deviceId: Unique device identifier
    /// - Returns: HSI JSON string or nil if Flux is not available
    public func whoopToHsi(_ json: String, timezone: String, deviceId: String) -> String? {
        guard isAvailable, let fn = whoopToHsiDaily else {
            print("[FluxFfi] whoopToHsi: Flux not available")
            return nil
        }

        return json.withCString { jsonPtr in
            timezone.withCString { tzPtr in
                deviceId.withCString { devicePtr in
                    guard let resultPtr = fn(jsonPtr, tzPtr, devicePtr) else {
                        if let errorFn = lastError, let errPtr = errorFn() {
                            print("[FluxFfi] whoopToHsi failed: \(String(cString: errPtr))")
                        }
                        return nil
                    }
                    let result = String(cString: resultPtr)
                    freeString?(resultPtr)
                    return result
                }
            }
        }
    }

    /// Process Garmin JSON and return HSI JSON (stateless)
    ///
    /// - Parameters:
    ///   - json: Raw Garmin API response JSON
    ///   - timezone: User's timezone (e.g., "America/Los_Angeles")
    ///   - deviceId: Unique device identifier
    /// - Returns: HSI JSON string or nil if Flux is not available
    public func garminToHsi(_ json: String, timezone: String, deviceId: String) -> String? {
        guard isAvailable, let fn = garminToHsiDaily else {
            print("[FluxFfi] garminToHsi: Flux not available")
            return nil
        }

        return json.withCString { jsonPtr in
            timezone.withCString { tzPtr in
                deviceId.withCString { devicePtr in
                    guard let resultPtr = fn(jsonPtr, tzPtr, devicePtr) else {
                        if let errorFn = lastError, let errPtr = errorFn() {
                            print("[FluxFfi] garminToHsi failed: \(String(cString: errPtr))")
                        }
                        return nil
                    }
                    let result = String(cString: resultPtr)
                    freeString?(resultPtr)
                    return result
                }
            }
        }
    }

    /// Create a new native processor handle
    internal func createProcessor(baselineWindowDays: Int) -> UnsafeMutableRawPointer? {
        guard isAvailable, let fn = processorNew else {
            print("[FluxFfi] createProcessor: Flux not available")
            return nil
        }
        return fn(Int32(baselineWindowDays))
    }

    /// Free a native processor handle
    internal func freeProcessor(_ handle: UnsafeMutableRawPointer?) {
        guard let handle = handle, let fn = processorFree else { return }
        fn(handle)
    }

    /// Process WHOOP data with a stateful processor
    internal func processWhoop(
        handle: UnsafeMutableRawPointer,
        json: String,
        timezone: String,
        deviceId: String
    ) -> String? {
        guard let fn = processorProcessWhoop else { return nil }

        return json.withCString { jsonPtr in
            timezone.withCString { tzPtr in
                deviceId.withCString { devicePtr in
                    guard let resultPtr = fn(handle, jsonPtr, tzPtr, devicePtr) else {
                        if let errorFn = lastError, let errPtr = errorFn() {
                            print("[FluxFfi] processWhoop failed: \(String(cString: errPtr))")
                        }
                        return nil
                    }
                    let result = String(cString: resultPtr)
                    freeString?(resultPtr)
                    return result
                }
            }
        }
    }

    /// Process Garmin data with a stateful processor
    internal func processGarmin(
        handle: UnsafeMutableRawPointer,
        json: String,
        timezone: String,
        deviceId: String
    ) -> String? {
        guard let fn = processorProcessGarmin else { return nil }

        return json.withCString { jsonPtr in
            timezone.withCString { tzPtr in
                deviceId.withCString { devicePtr in
                    guard let resultPtr = fn(handle, jsonPtr, tzPtr, devicePtr) else {
                        if let errorFn = lastError, let errPtr = errorFn() {
                            print("[FluxFfi] processGarmin failed: \(String(cString: errPtr))")
                        }
                        return nil
                    }
                    let result = String(cString: resultPtr)
                    freeString?(resultPtr)
                    return result
                }
            }
        }
    }

    /// Save processor baselines to JSON
    internal func saveBaselines(handle: UnsafeMutableRawPointer) -> String? {
        guard let fn = processorSaveBaselines else { return nil }

        guard let resultPtr = fn(handle) else {
            if let errorFn = lastError, let errPtr = errorFn() {
                print("[FluxFfi] saveBaselines failed: \(String(cString: errPtr))")
            }
            return nil
        }
        let result = String(cString: resultPtr)
        freeString?(resultPtr)
        return result
    }

    /// Load processor baselines from JSON
    internal func loadBaselines(handle: UnsafeMutableRawPointer, json: String) -> Bool {
        guard let fn = processorLoadBaselines else { return false }

        return json.withCString { jsonPtr in
            let result = fn(handle, jsonPtr)
            if result != 0 {
                if let errorFn = lastError, let errPtr = errorFn() {
                    print("[FluxFfi] loadBaselines failed: \(String(cString: errPtr))")
                }
                return false
            }
            return true
        }
    }

    /// Get the last error message from the native library
    public func getLastError() -> String? {
        guard let fn = lastError, let errPtr = fn() else { return nil }
        return String(cString: errPtr)
    }
}

// MARK: - Global Convenience

/// Check if Flux native library is available
public var isFluxAvailable: Bool {
    FluxFfi.shared.isAvailable
}

/// Get the Flux load error if any
public var fluxLoadError: String? {
    FluxFfi.shared.loadError
}
