-- Add optional agent and model attribution to progress posts.
ALTER TABLE progress_posts ADD COLUMN agent_label TEXT;
ALTER TABLE progress_posts ADD COLUMN model TEXT;
