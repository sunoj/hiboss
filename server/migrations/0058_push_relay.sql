-- Adds encrypted relay credentials to boss push devices.
-- Direct APNs registrations retain their existing token identity.
ALTER TABLE boss_devices ADD COLUMN relay_handle TEXT;
ALTER TABLE boss_devices ADD COLUMN push_key TEXT;
CREATE UNIQUE INDEX idx_boss_devices_relay_handle ON boss_devices(relay_handle);
