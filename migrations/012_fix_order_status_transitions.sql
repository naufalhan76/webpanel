-- ============================================
-- MIGRATION: Fix order_status_transitions schema
-- Version: 012
-- Date: 2025-04-25
-- Description: Add missing columns required by the application's INSERT
--              statements in src/lib/actions/orders.ts. The current live
--              schema only has from_status / to_status, so the audit
--              trail INSERTs were silently failing.
-- ============================================

BEGIN;

-- Add primary key column with default so existing rows don't break
ALTER TABLE order_status_transitions
  ADD COLUMN IF NOT EXISTS transition_id UUID DEFAULT gen_random_uuid();

-- Backfill PK on any existing rows (defaults only apply to new inserts pre-PK)
UPDATE order_status_transitions
SET transition_id = gen_random_uuid()
WHERE transition_id IS NULL;

ALTER TABLE order_status_transitions
  ALTER COLUMN transition_id SET NOT NULL;

ALTER TABLE order_status_transitions
  ADD CONSTRAINT order_status_transitions_pkey PRIMARY KEY (transition_id);

-- Add the columns the app expects to insert
ALTER TABLE order_status_transitions
  ADD COLUMN IF NOT EXISTS order_id TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS transition_date TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- Foreign key to orders (nullable so existing orphan rows are tolerated;
-- ON DELETE CASCADE so a deleted order also drops its transition history).
ALTER TABLE order_status_transitions
  ADD CONSTRAINT order_status_transitions_order_id_fkey
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE;

-- Helpful indexes for common queries
CREATE INDEX IF NOT EXISTS idx_order_status_transitions_order_id
  ON order_status_transitions(order_id);

CREATE INDEX IF NOT EXISTS idx_order_status_transitions_transition_date
  ON order_status_transitions(transition_date DESC);

COMMIT;
