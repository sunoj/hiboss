// Defines the status predicate shared by ask resolution and delivery paths.
// Exports OPEN_MESSAGE_STATUS, SENT_MESSAGE_STATUS and the monotonic receipt SET fragment.
// Depends only on the messages.status column contract.

export const OPEN_MESSAGE_STATUS = "status IN ('sent', 'delivered', 'read')";
export const SENT_MESSAGE_STATUS = "status = 'sent'";

/** SET fragment for a receipt (bind 'delivered' or 'read'): a read message never moves back. */
export const RECEIPT_STATUS_SET_SQL = "status = CASE WHEN status = 'read' THEN 'read' ELSE ? END";
