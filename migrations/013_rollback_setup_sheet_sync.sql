-- ============================================
-- ROLLBACK: Remove sheet-sync triggers
-- Version: 013
-- Date: 2025-04-25
-- ============================================

BEGIN;

-- Drop the trigger from every public table (idempotent).
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS sync_to_sheet ON public.%I', r.tablename);
  END LOOP;
END $$;

DROP FUNCTION IF EXISTS notify_sheet_sync();

-- Optional: clear the database GUC. Comment out if you want to preserve the URL config.
-- ALTER DATABASE postgres RESET app.sheet_sync_url;

COMMIT;
