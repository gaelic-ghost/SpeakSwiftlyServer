import Testing

// MARK: - Serialized Test Suite

/// Keep these lifecycle-heavy route and MCP tests serialized so Swift Testing
/// does not interleave independent hosts, MCP surfaces, and held-open requests.
@Suite(.serialized)
struct ServerTests {}
