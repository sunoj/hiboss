-- Reconcile option messages selected through legacy Telegram or Discord callbacks.
-- A matching boss-to-agent reply means the original option is globally resolved.

UPDATE messages AS parent
SET status = 'replied', updated_at = datetime('now')
WHERE parent.direction = 'agent_to_boss'
  AND parent.status IN ('sent', 'delivered', 'read')
  AND json_extract(parent.metadata, '$.options') IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM messages AS reply
    JOIN json_each(parent.metadata, '$.options') AS option
      ON option.value = reply.body
    WHERE reply.reply_to = parent.id
      AND reply.direction = 'boss_to_agent'
  );
