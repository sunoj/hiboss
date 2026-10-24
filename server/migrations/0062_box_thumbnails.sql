-- Stores one optional client-generated thumbnail per Box media item.
-- thumb_key names the R2 object; both columns stay NULL until a thumbnail is uploaded.
ALTER TABLE box_items ADD COLUMN thumb_key TEXT;
ALTER TABLE box_items ADD COLUMN thumb_bytes INTEGER;
