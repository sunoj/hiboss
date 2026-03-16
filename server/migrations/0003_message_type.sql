-- v0.5.1: Add type field for structured message types
ALTER TABLE messages ADD COLUMN type TEXT DEFAULT 'text';
