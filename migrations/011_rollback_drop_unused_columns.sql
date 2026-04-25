-- ============================================
-- ROLLBACK: Drop unused columns (schema cleanup)
-- Version: 011
-- Date: 2025-04-25
-- Description: Restore columns dropped in 011_drop_unused_columns.sql.
-- WARNING: This restores schema only. Any data in the dropped columns
--          is permanently lost; restored columns will be NULL.
-- ============================================

BEGIN;

-- order_addons
ALTER TABLE order_addons
  ADD COLUMN IF NOT EXISTS custom_item_name TEXT,
  ADD COLUMN IF NOT EXISTS custom_category TEXT,
  ADD COLUMN IF NOT EXISTS custom_description TEXT,
  ADD COLUMN IF NOT EXISTS added_by UUID,
  ADD COLUMN IF NOT EXISTS added_at TIMESTAMPTZ DEFAULT NOW();

-- service_records
ALTER TABLE service_records
  ADD COLUMN IF NOT EXISTS description_of_work TEXT;

-- user_management
ALTER TABLE user_management
  ADD COLUMN IF NOT EXISTS last_login TIMESTAMPTZ;

-- payments
ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS transaction_id VARCHAR;

COMMIT;
