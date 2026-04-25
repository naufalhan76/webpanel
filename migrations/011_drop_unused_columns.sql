-- ============================================
-- MIGRATION: Drop unused columns (schema cleanup)
-- Version: 011
-- Date: 2025-04-25
-- Description: Drop columns that have zero references in src/ codebase.
--              Identified by audit cross-referencing live Supabase schema
--              against all column usages (.select, .insert, .update, .eq,
--              type definitions, JSX renders) in src/.
-- ============================================

BEGIN;

-- order_addons: unused "custom add-on without catalog" feature columns +
-- unused audit metadata. The custom_* cols were placeholders for a feature
-- that was never implemented; added_by/added_at audit fields are never set
-- by application code.
ALTER TABLE order_addons
  DROP COLUMN IF EXISTS custom_item_name,
  DROP COLUMN IF EXISTS custom_category,
  DROP COLUMN IF EXISTS custom_description,
  DROP COLUMN IF EXISTS added_by,
  DROP COLUMN IF EXISTS added_at;

-- service_records: free-text field with zero references in entire repo.
ALTER TABLE service_records
  DROP COLUMN IF EXISTS description_of_work;

-- user_management: app does not track user login times.
ALTER TABLE user_management
  DROP COLUMN IF EXISTS last_login;

-- payments: payment-gateway transaction id is never set by the app
-- (current payment flow uses payment_records keyed off invoices).
ALTER TABLE payments
  DROP COLUMN IF EXISTS transaction_id;

COMMIT;
