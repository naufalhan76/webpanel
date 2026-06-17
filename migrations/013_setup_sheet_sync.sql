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
--   2. After running this migration, configure the Apps Script Web App URL:
--        UPDATE sheet_sync_config SET url = 'https://script.google.com/macros/s/<DEPLOYMENT_ID>/exec';
--      The function reads the URL from the config table on every fire,
--      so changes take effect immediately (no restart required).
--
-- Tables excluded from sync are listed in the `excluded` array in the
-- DO block at the bottom. To add a new table later, either:
--   - Re-run the DO block (idempotent: drops + recreates triggers); OR
--   - Manually run for one table:
--        CREATE TRIGGER sync_to_sheet
--        AFTER INSERT OR UPDATE OR DELETE ON public.<your_table>
--        FOR EACH ROW EXECUTE FUNCTION notify_sheet_sync();
--
-- Note on free tier: Supabase free tier does not grant superuser to the
-- `postgres` role, so `ALTER DATABASE ... SET app.foo = '...'` fails with
-- "permission denied". This migration uses a config table instead, which
-- works on every Supabase tier.
-- ============================================

BEGIN;

-- 1. Config table holding the webhook URL. Constrained to a single row
--    via the CHECK + PK on a constant (id = 1).
CREATE TABLE IF NOT EXISTS sheet_sync_config (
  id INTEGER PRIMARY KEY DEFAULT 1,
  url TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT single_row CHECK (id = 1)
);

-- Seed the single row (NULL url == sync disabled).
INSERT INTO sheet_sync_config (id, url) VALUES (1, NULL)
ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE sheet_sync_config IS
  'Single-row config for notify_sheet_sync trigger. Set url to the Apps Script Web App deployment URL to enable sync; set to NULL to disable.';

-- 2. The notify function. Generic: works for any table because TG_TABLE_NAME
--    and row_to_json(NEW)/row_to_json(OLD) handle all schemas dynamically.
CREATE OR REPLACE FUNCTION notify_sheet_sync()
RETURNS TRIGGER AS $$
DECLARE
  payload JSONB;
  webhook_url TEXT;
BEGIN
  -- Read URL from the config table on every fire so URL changes take
  -- effect immediately without re-creating triggers.
  SELECT url INTO webhook_url FROM sheet_sync_config WHERE id = 1;

  -- Skip silently if URL is not configured (lets you disable sync without
  -- dropping triggers).
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

  -- Fire-and-forget HTTP post via pg_net. pg_net.http_post returns
  -- immediately with a request_id; the actual HTTP exchange happens
  -- asynchronously, so a slow webhook does not block writes.
  PERFORM net.http_post(
    url := webhook_url,
    body := payload,
    headers := '{"Content-Type":"application/json"}'::jsonb
  );

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION notify_sheet_sync IS
  'Generic trigger: forwards row INSERT/UPDATE/DELETE to the Apps Script webhook configured in sheet_sync_config.';

-- 3. Attach the trigger to every public table EXCEPT the excluded list.
--    Idempotent: drops the trigger first if it already exists.
DO $$
DECLARE
  r RECORD;
  -- Tables you do NOT want to sync to sheets.
  -- Add things like internal/audit tables if you don't want them mirrored.
  excluded TEXT[] := ARRAY[
    'order_status_transitions',  -- audit trail; usually noisy in sheets
    'sheet_sync_config'           -- the config table itself
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
