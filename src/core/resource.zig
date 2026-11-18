//! Singleton resource access for system parameters.

/// Resolves the parameter type for a singleton resource.
///
/// - `Resource(T)`        -> `*const T` (read-only)
/// - `Resource(*const T)` -> `*const T` (read-only)
/// - `Resource(*T)`       -> `*T`       (mutable)
pub fn Resource(comptime R: type) type {
    return switch (@typeInfo(R)) {
        .pointer => R,
        else => *const R,
    };
}
