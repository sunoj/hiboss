// The live side of resolution handling: the notification center, ActivityKit and the inbox.
// Exports: DeliveredNotificationCenter, SystemDeliveredNotificationCenter, SystemResolutionEffects.
// Dependencies: UserNotifications, DecisionActivityManager, InboxStore.current.

import HibossKit
import UserNotifications

/// Delivered notifications as reconciliation reads them; tests substitute a fake.
@MainActor
protocol DeliveredNotificationCenter {
    func delivered() async -> [DeliveredNotificationRecord]
    func remove(identifiers: [String])
}

struct SystemDeliveredNotificationCenter: DeliveredNotificationCenter {
    func delivered() async -> [DeliveredNotificationRecord] {
        await UNUserNotificationCenter.current().deliveredNotifications().map {
            DeliveredAskNotifications.record(identifier: $0.request.identifier, date: $0.date,
                                             userInfo: $0.request.content.userInfo)
        }
    }

    func remove(identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

struct SystemResolutionEffects: ResolutionEffects {
    var center: any DeliveredNotificationCenter = SystemDeliveredNotificationCenter()

    func removeDeliveredNotifications(forAsk id: String) async {
        let identifiers = DeliveredAskNotifications.identifiers(in: await center.delivered(), forAsk: id)
        if !identifiers.isEmpty { center.remove(identifiers: identifiers) }
    }

    func endActivity(forAsk id: String) async {
        await DecisionActivityManager.end(messageID: id)
    }

    func markClosed(_ id: String) {
        InboxStore.current?.applyResolution(MessageID(rawValue: id))
    }
}
