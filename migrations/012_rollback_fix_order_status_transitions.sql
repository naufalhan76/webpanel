-- ============================================
-- ROLLBACK: Fix order_status_transitions schema
-- Version: 012
-- Date: 2025-04-25
-- Description: Restores the original composite PK (from_status, to_status)
--              and removes the audit-log columns added in 012.
-- WARNING: This will delete any rows whose (from_status, to_status) pair
--          is duplicated, since the original composite PK requires
--          uniqueness. Back up the table before rolling back if you've
--          accumulated audit data you want to keep:
--            CREATE TABLE order_status_transitions_backup AS
--              SELECT * FROM order_status_transitions;
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

-- Deduplicate (from_status, to_status) pairs before re-adding composite PK.
DELETE FROM order_status_transitions a
USING order_status_transitions b
WHERE a.ctid < b.ctid
  AND a.from_status = b.from_status
  AND a.to_status = b.to_status;

ALTER TABLE order_status_transitions
  ADD CONSTRAINT pk_order_status_transitions PRIMARY KEY (from_status, to_status);

COMMIT;
