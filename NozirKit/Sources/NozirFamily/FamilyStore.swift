import Foundation
import Observation

/// The family's children for this session, in memory only (nothing about a
/// child is written to disk). Screens read it; whoever changes a child on the
/// server tells it.
@MainActor
@Observable
public final class FamilyStore {
    public private(set) var children: [Child] = []
    public private(set) var hasLoaded = false
    public let service: any FamilyService

    public init(service: any FamilyService) {
        self.service = service
    }

    /// Asks the server. A failure keeps what was there and is rethrown.
    public func refresh() async throws {
        let fresh = try await service.children()
        children = fresh
        hasLoaded = true
    }

    public func child(_ id: UUID) -> Child? {
        children.first { $0.id == id }
    }

    public func replace(_ child: Child) {
        if let index = children.firstIndex(where: { $0.id == child.id }) {
            children[index] = child
        } else {
            children.append(child)
        }
    }

    public func remove(_ id: UUID) {
        children.removeAll { $0.id == id }
    }
}
