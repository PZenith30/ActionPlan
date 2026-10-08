# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-page static dashboard (Thai UI) tracking the Rubber Authority of Thailand (กยท.) FY2569 action plan. Everything — HTML, CSS, JS — lives in one file, `index.html`. No build, no package manager, no tests; libraries come from cdnjs (only Chart.js loads upfront; SheetJS is loaded via `loadScriptOnce()` when the Excel button is clicked; ExcelJS, html2canvas, jsPDF are lazy-loaded via the `LIBS` map when a report is generated). Viewers open it from a monthly LINE alert, mostly in LINE's in-app browser on phones, so first-load speed matters — don't add blocking scripts to `<head>`.

The user's constraint: nothing may be installed — keep it a plain static file deployable on Vercel, and talk to Supabase with plain `fetch` against the REST API (no supabase-js, no npm).

## Data flow

```
Google Sheet "Data ACP69" --(Apps Script, on menu click)--> Supabase public.sheet_snapshots <--(anon key, read-only)-- index.html
```

- Staff edit the Google Sheet. The bound Apps Script (local file `AppScript`, pasted into the Sheet's script editor by the user) pushes every sheet in `SYNC_SHEETS` to Supabase when the user runs **📁 เมนูระบบ > บันทึกผลการดำเนินงานย้อนหลัง** (`runArchiveProcess` calls `syncToSupabaseLogged` at the end) or **ส่งข้อมูลขึ้นเว็บ (Supabase) เดี๋ยวนี้**. Results are appended to the `ประวัติการบันทึก` sheet.
- `supabase/schema.sql` defines the single table: one row per sheet, `headers` (ordered array) + `rows` (array of arrays of display strings, i.e. what `getDisplayValues()` returns — same as the old gviz CSV export). All sheets are sent in one upsert, so the dashboard never sees a half-updated set. RLS: `select` for anon/authenticated only; writes need the service_role / `sb_secret_` key, stored only in the Apps Script's Script Properties (`SUPABASE_SECRET_KEY`).
- Don't store emails or other personal data in `sheet_snapshots` — the anon key is public, so anyone can read the table.
- Visitor stats: an inline script at the top of `<head>` (which also defines `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `requestSnapshots()` and starts `earlySnapshotsRequest` so data downloads in parallel with Chart.js/fonts) calls `rpc/log_page_view` after `load`. The function is `security definer`; anon has no direct access to `page_views`, and the `page_view_monthly` / `page_view_daily` views are `security_invoker`, so stats are visible only inside Supabase. Only a random per-device id (localStorage `acp-visitor`), source (`?src=` or LINE user agent) and an is-mobile flag are stored.
- `indexAppScript` is a separate Apps Script HTML page (Early Warning / LINE alerts), not part of the Vercel site. `AppScript` also references dialog files (`ArchiveDialog`, `CancelDialog`) that exist only in the Apps Script project.

## Source of truth: `Note`

The user edits the dashboard in the local file `Note` (git-ignored). `index.html` is a straight copy of it: when `Note` changes, `cp Note index.html`, then commit and push. Make dashboard edits in `Note` and copy; don't let the two diverge.

## Run / deploy

- Preview: open `index.html` in a browser. It needs network access to Supabase and cdnjs.
- Deploy: Vercel, Framework Preset **Other**, empty build command and output directory; pushing to `main` redeploys. `vercel.json` only sets headers (`X-Robots-Tag: noindex, nofollow`, `nosniff`, `no-referrer`) and `cleanUrls`. If a CSP is ever added, it must allow cdnjs, Google Fonts and `*.supabase.co`.
- No Node/Python on this machine. To smoke-test JS, run headless Chrome (`chrome.exe --headless=new --dump-dom file:///…`) and read the console via `--enable-logging=stderr`.

## Architecture of `index.html`

Several `<script>` blocks, in order:
1. View switching (`activateView`) for the left nav: `view-dashboard`, `view-annual`, `view-masterplan`, `view-dgarea` (PA/MOU, grouped by executive).
2. Report generator IIFE (PDF/Excel, A4 landscape): picks fiscal year + month from current data or the history sheet; topics in `TOPICS`.
3. `window.ACPDash` — rendering module; `ACPDash.start({records, strategies, orgKpis, historyPeriods, masterPlans})` draws everything.
4. Loader (last block): `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SHEET_SPECS`, then `loadAndRender()` → `fetchSheetBySpec()` per sheet → `buildDashboardData()` / `buildOrgKpis()` / `buildHistoryDataset()` → `ACPDash.start()`. Errors show `#errorOverlay`.

Loader behaviours worth knowing:
- `loadSnapshots()` fetches all rows of `sheet_snapshots` once. `fetchSheetRows(name)` rebuilds `{header: value}` objects plus `__fields` (column order), the same shape Papa.parse used to produce, so the `build*` functions are unchanged. Column order matters: the `ส่วนงานภายใต้ผู้บริหาร` matrix uses `__fields[0]` as the owner column and the rest as executives.
- `fetchHistorySheetRaw()` returns raw arrays (no header row); `buildHistoryDataset()` reads `ผลการดำเนินงานย้อนหลัง` by column position A–T (layout written by the Apps Script archive; N–P are ARRAYFORMULA columns in the sheet).
- Each `SHEET_SPECS` entry lists alternate sheet names and `required` headers; a missing sheet yields an empty array and is skipped if `optional`. Keep sheet names in sync with `SYNC_SHEETS` in `AppScript`.
- Only the latest `Fiscal_Year` found in the projects sheet is kept.
- Cancelled projects: if any row of a project in `โครงการ` has `สถานะโครงการ` containing "ยกเลิก", `buildDashboardData()` drops the project from `records` (so it's excluded from every stat, chart and history view via `window.ACP_CANCELLED`) and pushes its details (name, owner, budget, `เหตุผลการยกเลิก`) to `window.ACP_CANCELLED_LIST`. The 5th card on the main dashboard (`#cancelledCard`, opens `#cancelModal`) shows that list. Some project codes appear on several rows of the projects sheet.
- `#kpiGrid` alone has 5 cards: 5 columns at ≥1440px, 3+2 at 1001–1439px, then the shared `.kpi-grid` rules (2 columns with the 5th card full-width, 1 column ≤380px). Other `.kpi-grid`s stay at 4 columns.
- `normCode()` re-pads numeric project codes to 6 digits (e.g. `010101`), since leading zeros get lost in Sheets.
- `isYes()` interprets checkbox-like cells (TRUE/Yes/✓/ใช่…).
- Status levels are Thai strings: `['ดีมาก','ดี','พอใช้','ต้องปรับปรุง']`.

## Files that must stay out of the repo

Per `.gitignore`: `Note`, `ACP/` (source exports), `แดชบอร์ดแผนปฏิบัติการ-กยท-2569.html` (contains staff emails), `*.ps1`, `*.png`, `scratchpad/`, `.vercel`. Never commit a Supabase service_role / secret key.

## Conventions

- Commit messages are written in Thai.
- UI text is Thai; dates use the Buddhist calendar (2569 = 2026).
