# Operations Runbook

Setup procedures for free-tier Supabase + ops glue. All steps are one-time
unless noted.

---

## 1. Anti-pause: cron-job.org (5 minutes)

Supabase free tier pauses a project after **7 days** with no DB activity.
A cheap and reliable workaround: ping the REST API every 6 hours.

### Steps

1. Sign up at https://cron-job.org (free).
2. **Create cronjob** → Common settings:
   - **Title**: `webpanel anti-pause`
   - **URL**: `https://ybxnosmcjubuezefofko.supabase.co/rest/v1/customers?select=customer_id&limit=1`
   - **Schedule**: every 6 hours (Advanced → "0 */6 * * *")
   - **Request method**: GET
3. **Headers tab** → add:
   - `apikey`: paste the **anon key** from Supabase Dashboard → Project Settings → API
4. **Save**.
5. Click **Run now** to verify. Expected response: `200 OK` with `[]` or `[{ "customer_id": "..." }]`.

### Verify weekly

cron-job.org keeps a 100-event execution log per job. Check it once a week
to make sure the pings are still 200 OK. If it starts returning 401, the
anon key was rotated and the job needs the new key.

---

## 2. Daily DB backup → Google Drive (1 hour, optional)

Supabase free tier does not include automatic backups. Recommended setup:
GitHub Actions cron + `pg_dump` + rclone to Google Drive.

> Not yet implemented. See `.github/workflows/db-backup.yml` (TODO).

Required secrets when added:
- `DB_PASSWORD`: Supabase Dashboard → Settings → Database → Connection Pooler → **Direct connection** password.
- `RCLONE_CONFIG`: output of `rclone config` for a Google Drive remote.

Cost: free (within 2000 GitHub Actions minutes/month and 15 GB Drive).

---

## 3. Spreadsheet sync via Postgres triggers + Apps Script

Mirrors every INSERT/UPDATE/DELETE on application tables into a Google
Sheet (one sheet per table). Real-time (1–3 second latency). Selective via
the `excluded` list in the trigger setup migration.

### Architecture

```
   Postgres                   pg_net                   Apps Script
  ┌─────────┐ AFTER trigger  ┌───────┐ HTTP POST     ┌────────────┐
  │ tables  │───────────────>│notify_│──────────────>│ doPost(e)  │
  │ (any)   │                │sheet_ │               │ → Sheet    │
  └─────────┘                │sync() │               └────────────┘
                             └───────┘
```

The `notify_sheet_sync` Postgres function is generic — it works for any
table in `public` because it uses `TG_TABLE_NAME` and `row_to_json(NEW)`
to build the payload dynamically. New tables get the trigger applied via
the idempotent `DO` block at the bottom of `migrations/013_setup_sheet_sync.sql`.

### One-time setup

#### 3.1. Enable pg_net extension

Supabase Dashboard → **Database** → **Extensions** → search `pg_net` →
**Enable**. (No migration command — Supabase manages this through the UI.)

#### 3.2. Create the destination Google Sheet + Apps Script

1. Create a new Google Sheet (or open an existing reporting sheet).
2. **Extensions** → **Apps Script** to open the editor.
3. Replace the default `Code.gs` content with the contents of
   [`scripts/sheet-sync.gs`](../scripts/sheet-sync.gs).
4. **Save** (Ctrl+S). Name the project anything (e.g. "webpanel sync").

#### 3.3. Deploy the Apps Script as a Web App

1. In the Apps Script editor: **Deploy** → **New deployment**.
2. Click the gear ⚙ icon next to "Select type" → **Web app**.
3. Configure:
   - **Description**: `webpanel sheet sync v1`
   - **Execute as**: **Me** (your Google account)
   - **Who has access**: **Anyone** (this is required so Postgres can reach it; the URL itself is the auth secret)
4. Click **Deploy**, authorize when prompted (Google will warn about an "unverified app" — proceed; you wrote it).
5. **Copy** the deployment URL. It looks like:
   `https://script.google.com/macros/s/AKfycb.../exec`

#### 3.4. Sanity-check the Apps Script

In a browser, paste the deployment URL. You should get:
```json
{"ok":true,"ts":"2025-04-25T..."}
```
If you get a Google login page or an HTML error page, redeploy with **Who
has access: Anyone**.

#### 3.5. Tell Postgres where to send events

In Supabase Dashboard → **SQL Editor**, run **once**:

```sql
ALTER DATABASE postgres
  SET app.sheet_sync_url = 'https://script.google.com/macros/s/<YOUR_DEPLOYMENT_ID>/exec';
```

Then **restart the database**: Settings → Database → "Restart project".
This is required for the `ALTER DATABASE ... SET` to take effect on
existing connections.

#### 3.6. Apply the trigger migration

In SQL Editor, paste and run `migrations/013_setup_sheet_sync.sql`. This
creates `notify_sheet_sync()` and attaches `sync_to_sheet` triggers to
every public table except those in the `excluded` array.

#### 3.7. Test

Make any change in the app (e.g. add a customer). Within 1–3 seconds, a
row should appear in the `customers` sheet of your spreadsheet. If a
sheet for that table didn't exist, it will be auto-created with headers.

### Adding a new table later

When you create a new table in Postgres, **re-run** the `DO $$ ... $$;`
block at the bottom of `migrations/013_setup_sheet_sync.sql`. It is
idempotent (drops the trigger first if present), so re-running is safe.

Or, for a single table:

```sql
CREATE TRIGGER sync_to_sheet
AFTER INSERT OR UPDATE OR DELETE ON public.<your_table>
FOR EACH ROW EXECUTE FUNCTION notify_sheet_sync();
```

### Excluding a table from sync

Edit the `excluded` array in the migration file and re-run. By default,
`order_status_transitions` is excluded (audit trail, not useful in sheets).

### Disabling sync without dropping triggers

Clear the URL setting:

```sql
ALTER DATABASE postgres SET app.sheet_sync_url = '';
```

The trigger function checks for an empty URL and returns early, so events
will not be sent. Restore later by setting the URL again.

### Removing entirely

Run `migrations/013_rollback_setup_sheet_sync.sql`. Drops every
`sync_to_sheet` trigger and the `notify_sheet_sync` function. The
`pg_net` extension stays enabled (other things may use it).

### Troubleshooting

- **Sheet not updating after a change**: check Apps Script editor →
  Executions tab. Look for failed runs and read the error.
- **Postgres errors**: Supabase Dashboard → Logs Explorer → filter by
  `pg_net`. The `net._http_response` table also records every outgoing
  request and the response status.
- **Bulk operations stall**: pg_net queues HTTP requests asynchronously
  but has a soft limit on queue length. Large bulk INSERTs can drop
  events under load. For ETL-style migrations, temporarily disable sync
  via the URL clear above.
- **Apps Script quota**: free Apps Script gives 6 minutes execution per
  request and 30 minutes total per day for triggers. Each webhook call is
  <1 second; you'd need ~1800 events/day to hit the cap.
