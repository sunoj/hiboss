// Resolves agent message attachments from the session stream without requiring cached history.
// Exports: SessionEvent.messageAttachment, using the shared URL validation and file classification.
// Dependencies: HibossKit SessionEvent, AnyJSON and MessageAttachment.

import HibossKit

extension SessionEvent {
    var messageAttachment: MessageAttachment? {
        guard kind == "message", direction == "agent_to_boss",
              let url = payload?.objectValue?["metadata"]?.objectValue?["file_url"]?.stringValue else {
            return nil
        }
        return MessageAttachment(urlString: url)
    }
}
