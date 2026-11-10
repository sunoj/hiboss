// Resolves agent message attachments from the session stream without requiring cached history.
// Exports: SessionEvent.messageAttachment with its optional display copy, using shared URL validation.
// Dependencies: HibossKit SessionEvent, AnyJSON and MessageAttachment.

import HibossKit

extension SessionEvent {
    var messageAttachment: MessageAttachment? {
        guard kind == "message", direction == "agent_to_boss",
              let metadata = payload?.objectValue?["metadata"]?.objectValue,
              let url = metadata["file_url"]?.stringValue else {
            return nil
        }
        return MessageAttachment(urlString: url, thumbnailURLString: metadata["file_thumbnail_url"]?.stringValue)
    }
}
