// Decodes the message snapshot carried by a non-private APNs notification.
// Exports: PushMessageSnapshot.decode for zero-network detail cache prewarming.
// Dependencies: Foundation JSON bridging and HibossKit message contracts.

import Foundation
import HibossKit

enum PushMessageSnapshot {
    static func decode(from userInfo: [AnyHashable: Any]) -> MessageDetail? {
        guard let value = userInfo["message"], JSONSerialization.isValidJSONObject(value) else {
            return nil
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: value)
            let message = try JSONDecoder().decode(HistoryMessage.self, from: data)
            return MessageDetail(message: message, replies: [])
        } catch {
            return nil
        }
    }
}
