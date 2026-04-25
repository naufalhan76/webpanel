-- ============================================
-- ROLLBACK: Fix order_status_transitions schema
-- Version: 012
-- Date: 2025-04-25
-- ============================================

BEGIN;

DROP INDEX IF EXISTS idx_order_status_transitions_transition_date;
DROP INDEX IF EXISTS idx_order_status_transitions_order_id;

ALTER TABLE order_status_transitions
  DROP CONSTRAINT IF EXISTS order_status_transitions_order_id_fkey;

ALTER TABLE order_status_transitions
  DROP CONSTRAINT IF EXISTS order_status_transitions_pkey;

ALTER TABLE order_status_transitions
  DROP COLUMN IF EXISTS created_at,
  DROP COLUMN IF EXISTS transition_date,
  DROP COLUMN IF EXISTS notes,
  DROP COLUMN IF EXISTS order_id,
  DROP COLUMN IF EXISTS transition_id;

COMMIT;
