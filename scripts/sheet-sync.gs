/**
 * Google Apps Script — Sheet sync handler for webpanel.
 *
 * Receives webhooks from Postgres `notify_sheet_sync` trigger and mirrors
 * INSERT / UPDATE / DELETE events into the bound spreadsheet, one sheet
 * per Postgres table (auto-created on first event).
 *
 * Setup:
 *   1. Open the target Google Sheet.
 *   2. Extensions -> Apps Script. Paste this whole file.
 *   3. Save (Ctrl+S), then Deploy -> New deployment.
 *      Type: Web app
 *      Execute as: Me
 *      Who has access: Anyone (required for Postgres pg_net to reach it)
 *   4. Copy the deployment URL.
 *   5. In Supabase SQL Editor, run:
 *        ALTER DATABASE postgres SET app.sheet_sync_url = '<the URL>';
 *      Then RESTART the Postgres pool (Settings -> Database -> Restart project).
 *
 * Re-deploy:
 *   When you change this script, Deploy -> Manage deployments -> edit existing
 *   deployment -> Version: New version. The URL stays the same.
 *
 * Notes:
 *   - `record` and `old_record` are passed as objects keyed by column name.
 *   - Primary key is detected as the first column whose name ends in '_id' or
 *     equals 'id'. If your table uses a different PK pattern, edit
 *     `findPrimaryKey()` below.
 *   - DELETE events match by the OLD row's primary key.
 *   - Header row is auto-created on first INSERT into a new sheet.
 */

function doPost(e) {
  try {
    const payload = JSON.parse(e.postData.contents);
    const tableName = payload.table;
    const op = payload.type; // 'INSERT' | 'UPDATE' | 'DELETE'
    const record = payload.record;
    const oldRecord = payload.old_record;

    if (!tableName || !op) {
      return jsonResponse({ ok: false, error: 'missing table or type' });
    }

    const ss = SpreadsheetApp.getActive();
    let sheet = ss.getSheetByName(tableName);

    if (op === 'INSERT') {
      handleInsert(ss, sheet, tableName, record);
    } else if (op === 'UPDATE') {
      if (!sheet) {
        // Sheet doesn't exist yet — fall back to insert
        handleInsert(ss, sheet, tableName, record);
      } else {
        handleUpdate(sheet, record, oldRecord);
      }
    } else if (op === 'DELETE') {
      if (sheet) handleDelete(sheet, oldRecord);
    } else {
      return jsonResponse({ ok: false, error: 'unknown op: ' + op });
    }

    return jsonResponse({ ok: true });
  } catch (err) {
    console.error(err);
    return jsonResponse({ ok: false, error: String(err) });
  }
}

function handleInsert(ss, sheet, tableName, record) {
  const headers = Object.keys(record);
  if (!sheet) {
    sheet = ss.insertSheet(tableName);
    sheet.appendRow(headers);
    sheet.setFrozenRows(1);
  }
  // Use the existing header order if sheet was already there with a header row
  const existingHeaders = sheet.getRange(1, 1, 1, sheet.getLastColumn() || 1)
    .getValues()[0]
    .filter(String);
  const orderedHeaders = existingHeaders.length > 0 ? existingHeaders : headers;
  const row = orderedHeaders.map(function (h) {
    return record[h] === undefined ? '' : record[h];
  });
  sheet.appendRow(row);
}

function handleUpdate(sheet, record, oldRecord) {
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) {
    sheet.appendRow(Object.keys(record));
    sheet.setFrozenRows(1);
    sheet.appendRow(Object.values(record));
    return;
  }
  const headers = data[0];
  const pkCol = findPrimaryKey(headers);
  if (pkCol === -1) {
    // No PK: append as new row
    sheet.appendRow(headers.map(function (h) { return record[h] === undefined ? '' : record[h]; }));
    return;
  }
  const pkValue = (oldRecord && oldRecord[headers[pkCol]] !== undefined)
    ? oldRecord[headers[pkCol]]
    : record[headers[pkCol]];

  for (let i = 1; i < data.length; i++) {
    if (String(data[i][pkCol]) === String(pkValue)) {
      const newRow = headers.map(function (h) {
        return record[h] === undefined ? '' : record[h];
      });
      sheet.getRange(i + 1, 1, 1, headers.length).setValues([newRow]);
      return;
    }
  }
  // Not found: treat as insert
  sheet.appendRow(headers.map(function (h) { return record[h] === undefined ? '' : record[h]; }));
}

function handleDelete(sheet, oldRecord) {
  if (!oldRecord) return;
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return;
  const headers = data[0];
  const pkCol = findPrimaryKey(headers);
  if (pkCol === -1) return;
  const pkValue = oldRecord[headers[pkCol]];
  for (let i = data.length - 1; i >= 1; i--) {
    if (String(data[i][pkCol]) === String(pkValue)) {
      sheet.deleteRow(i + 1);
      return;
    }
  }
}

function findPrimaryKey(headers) {
  // Heuristic: prefer a column ending in '_id', then 'id'. Customize if your
  // tables use a different naming convention.
  for (let i = 0; i < headers.length; i++) {
    if (typeof headers[i] === 'string' && /_id$/.test(headers[i])) return i;
  }
  for (let i = 0; i < headers.length; i++) {
    if (headers[i] === 'id') return i;
  }
  return -1;
}

function jsonResponse(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * Optional: GET handler for health check.
 * Open the deployment URL in a browser to confirm it's live.
 */
function doGet() {
  return jsonResponse({ ok: true, ts: new Date().toISOString() });
}
