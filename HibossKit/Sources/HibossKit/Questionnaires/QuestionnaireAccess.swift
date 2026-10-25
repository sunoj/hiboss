// Decides whether the signed-in boss may answer a panel's questionnaire, mirroring the server.
// Exports BossIdentity (the `/api/boss/me` id and role), QuestionnaireAccess with its reason, and
// the read-only form that omits submit controls.
// Dependencies: Foundation and the package string catalog.

import Foundation

public struct BossIdentity: Decodable, Equatable, Sendable {
    public let id: String
    public let role: String

    public init(id: String, role: String) {
        self.id = id
        self.role = role
    }
}

/// Only the panel's target boss with role admin or manager may submit; everyone else reads.
public enum QuestionnaireAccess: Equatable, Sendable {
    case answerable
    case otherBoss
    case roleCannotAnswer

    public init(boss: BossIdentity, targetBossID: String) {
        if boss.id != targetBossID {
            self = .otherBoss
        } else if boss.role == "admin" || boss.role == "manager" {
            self = .answerable
        } else {
            self = .roleCannotAnswer
        }
    }

    public var readOnlyReason: String? {
        switch self {
        case .answerable: nil
        case .otherBoss: kitL("Only the boss this panel is for can answer it.")
        case .roleCannotAnswer: kitL("Your role can view these questions but not answer them.")
        }
    }
}

extension PanelSpec {
    /// The form without elements that submit it, and without references to them.
    func removingSubmitControls() -> PanelSpec {
        let submits = Set(elements.filter { $0.value.on?["press"]?.action == "submitRequest" }.keys)
        guard !submits.isEmpty else { return self }
        var kept: [String: PanelElement] = [:]
        for (id, element) in elements where !submits.contains(id) {
            kept[id] = PanelElement(type: element.type, props: element.props,
                                    children: element.children.filter { !submits.contains($0) }, on: element.on)
        }
        return PanelSpec(root: root, elements: kept)
    }
}
