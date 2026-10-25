// Decides whether the signed-in boss may answer a panel's questionnaire, mirroring the server.
// Exports BossIdentity (the `/api/boss/me` id and role) and QuestionnaireAccess with its reason.
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
