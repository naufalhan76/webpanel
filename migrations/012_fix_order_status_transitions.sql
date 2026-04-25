-- ============================================
-- MIGRATION: Fix order_status_transitions schema
-- Version: 012
-- Date: 2025-04-25
-- Description: Repurpose order_status_transitions from a misshapen
--              "valid transitions" lookup (composite PK on
--              (from_status, to_status)) into a proper audit log of
--              order status changes.
--
--              Background: the table was originally created with the
--              composite PK above and only those two columns. The
--              application's INSERTs in src/lib/actions/orders.ts pass
--              order_id, notes, transition_date as well — the inserts
--              have been failing silently (no error check) on every
--              status change. The table is never read FROM in code, so
--              repurposing it is safe.
-- ============================================

BEGIN;

-- 1. Drop the old composite primary key. Existing rows (if any) are
--    preserved as regular non-key columns; from_status/to_status no
--    longer need to be unique together.
ALTER TABLE order_status_transitions
  DROP CONSTRAINT IF EXISTS pk_order_status_transitions;

-- 2. Add the columns the application expects.
ALTER TABLE order_status_transitions
  ADD COLUMN IF NOT EXISTS transition_id UUID DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS order_id TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS transition_date TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- 3. Backfill transition_id on any pre-existing rows so we can make it NOT NULL.
UPDATE order_status_transitions
SET transition_id = gen_random_uuid()
WHERE transition_id IS NULL;

ALTER TABLE order_status_transitions
  ALTER COLUMN transition_id SET NOT NULL;

-- 4. Set the new primary key.
ALTER TABLE order_status_transitions
  ADD CONSTRAINT order_status_transitions_pkey PRIMARY KEY (transition_id);

-- 5. Foreign key to orders. Nullable so legacy rows with no order_id
--    are tolerated; ON DELETE CASCADE so deleting an order also drops
--    its transition history.
ALTER TABLE order_status_transitions
  ADD CONSTRAINT order_status_transitions_order_id_fkey
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE;

-- 6. Indexes for common queries.
CREATE INDEX IF NOT EXISTS idx_order_status_transitions_order_id
  ON order_status_transitions(order_id);

CREATE INDEX IF NOT EXISTS idx_order_status_transitions_transition_date
  ON order_status_transitions(transition_date DESC);

COMMIT;
