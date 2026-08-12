import Foundation

enum VitalsCollectError: Error, Equatable {
    case nullPointer
    case invalidUTF8
    /// The `{"schemaVersion":...,"error":...}` shape `vitals_collect`
    /// returns when `vitals-core` itself failed (e.g. a probe error).
    case reported(String)
    case malformed
}

/// Calls into `vitals-ffi` and decodes its JSON response. `decode(_:)` is
/// kept separate from `collect()` so the JSON-handling logic is testable
/// without going through the real FFI call (which shells out to system
/// commands).
enum VitalsBridge {
    static func collect() -> Result<VitalsReport, VitalsCollectError> {
        guard let ptr = vitals_collect() else {
            return .failure(.nullPointer)
        }
        defer { vitals_free_string(ptr) }
        return decode(String(cString: ptr))
    }

    static func decode(_ json: String) -> Result<VitalsReport, VitalsCollectError> {
        guard let data = json.data(using: .utf8) else {
            return .failure(.invalidUTF8)
        }
        if let report = try? JSONDecoder().decode(VitalsReport.self, from: data) {
            return .success(report)
        }
        if let apiError = try? JSONDecoder().decode(VitalsAPIError.self, from: data) {
            return .failure(.reported(apiError.error))
        }
        return .failure(.malformed)
    }
}
