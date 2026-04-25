-- ============================================
-- MIGRATION: Set up generic sheet-sync triggers
-- Version: 013
-- Date: 2025-04-25
-- Description: Forwards every INSERT/UPDATE/DELETE on application tables
--              to a Google Apps Script Web App via pg_net.http_post.
--              The Apps Script handler upserts rows into a sheet named
--              after the table.
--
-- Prerequisites:
--   1. Enable the pg_net extension once via:
--        Supabase Dashboard -> Database -> Extensions -> search "pg_net" -> Enable
--   2. Set a database GUC with the Apps Script Web App URL once:
--        ALTER DATABASE postgres SET app.sheet_sync_url = 'https://script.google.com/macros/s/<DEPLOYMENT_ID>/exec';
--      (Or hardcode the URL inside notify_sheet_sync below.)
--
-- Tables excluded from sync are listed in the `excluded` array in the
-- DO block at the bottom. To add a new table later, either:
--   - Re-run this DO block (it is idempotent: drops + recreates triggers); OR
--   - Manually run for one table:
--        CREATE TRIGGER sync_to_sheet
--        AFTER INSERT OR UPDATE OR DELETE ON public.<your_table>
--        FOR EACH ROW EXECUTE FUNCTION notify_sheet_sync();
-- ============================================

BEGIN;

-- The notify function. Generic: works for any table because TG_TABLE_NAME
-- and row_to_json(NEW)/row_to_json(OLD) handle all schemas dynamically.
CREATE OR REPLACE FUNCTION notify_sheet_sync()
RETURNS TRIGGER AS $$
DECLARE
  payload JSONB;
  webhook_url TEXT;
BEGIN
  -- Read URL from database GUC (set with ALTER DATABASE ... SET app.sheet_sync_url = '...')
  webhook_url := current_setting('app.sheet_sync_url', true);

  -- Skip silently if URL is not configured (lets you disable sync without dropping triggers)
  IF webhook_url IS NULL OR webhook_url = '' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  payload := jsonb_build_object(
    'table', TG_TABLE_NAME,
    'type', TG_OP,
    'record', CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE row_to_json(NEW) END,
    'old_record', CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN row_to_json(OLD) ELSE NULL END,
    'timestamp', extract(epoch FROM now())
  );

  -- Fire-and-forget HTTP post via pg_net. Failure does NOT abort the trigger
  -- because pg_net.http_post returns immediately with a request_id.
  PERFORM net.http_post(
    url := webhook_url,
    body := payload,
    headers := '{"Content-Type":"application/json"}'::jsonb
  );

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION notify_sheet_sync IS
  'Generic trigger: forwards row INSERT/UPDATE/DELETE to the Apps Script webhook configured at app.sheet_sync_url.';

-- Attach the trigger to every public table EXCEPT the excluded list.
-- Idempotent: drops the trigger first if it already exists.
DO $$
DECLARE
  r RECORD;
  -- Tables you do NOT want to sync to sheets.
  -- Add things like internal/audit tables if you don't want them mirrored.
  excluded TEXT[] := ARRAY[
    'order_status_transitions'  -- audit trail; usually noisy and not useful in sheets
  ];
BEGIN
  FOR r IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename != ALL(excluded)
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS sync_to_sheet ON public.%I', r.tablename);
    EXECUTE format(
      'CREATE TRIGGER sync_to_sheet
       AFTER INSERT OR UPDATE OR DELETE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION notify_sheet_sync()',
      r.tablename
    );
  END LOOP;
END $$;

COMMIT;
