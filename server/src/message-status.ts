// Defines the status predicate shared by ask resolution and delivery paths.
// Exports OPEN_MESSAGE_STATUS and SENT_MESSAGE_STATUS SQL fragments.
// Depends only on the messages.status column contract.

export const OPEN_MESSAGE_STATUS = "status IN ('sent', 'delivered', 'read')";
export const SENT_MESSAGE_STATUS = "status = 'sent'";
