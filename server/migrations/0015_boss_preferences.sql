-- Boss preferences: per-boss channel and notification settings
ALTER TABLE bosses ADD COLUMN preferences TEXT DEFAULT NULL;
