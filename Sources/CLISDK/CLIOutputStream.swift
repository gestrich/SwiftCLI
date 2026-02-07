import Foundation

/// A multi-subscriber output stream for CLI operations.
/// Each call to `makeStream()` creates an independent AsyncStream that receives all future output.
/// This follows the same pattern as NotificationCenter.notifications().
///
/// Usage:
/// ```swift
/// let output = CLIOutputStream()
///
/// // Subscriber 1
/// Task {
///     for await item in await output.makeStream() {
///         print("Subscriber 1: \(item)")
///     }
/// }
///
/// // Subscriber 2
/// Task {
///     for await item in await output.makeStream() {
///         print("Subscriber 2: \(item)")
///     }
/// }
///
/// // Producer
/// await output.send(.stdout("Hello"))
/// await output.send(.stdout("World"))
/// ```
public actor CLIOutputStream {
    private var continuations: [UUID: AsyncStream<StreamOutput>.Continuation] = [:]

    public init() {}

    /// Create a new stream for a subscriber.
    /// Each subscriber gets their own independent stream.
    /// The stream receives all output from the point of subscription forward.
    public func makeStream() -> AsyncStream<StreamOutput> {
        let id = UUID()

        return AsyncStream { continuation in
            // Register this subscriber
            self.continuations[id] = continuation

            // Clean up when consumer stops iterating
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.unregister(id: id)
                }
            }
        }
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Send output to all active subscribers
    public func send(_ output: StreamOutput) {
        for continuation in continuations.values {
            continuation.yield(output)
        }
    }

    /// Finish all active streams (optional - for cleanup)
    public func finishAll() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    /// Number of active subscribers (useful for debugging)
    public var subscriberCount: Int {
        continuations.count
    }
}
