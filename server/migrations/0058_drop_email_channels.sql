-- Email never had a delivery adapter and is no longer a configurable channel.
-- Remove the configs and routing rules that name it; message history keeps its channel value.
DELETE FROM channel_configs WHERE channel = 'email';
DELETE FROM routing_rules WHERE channel = 'email';
