# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-page static dashboard (Thai UI) tracking the Rubber Authority of Thailand (กยท.) FY2569 action plan. Everything — HTML, CSS, JS — lives in one file, `index.html`. The data is **not** in the repo: it is fetched live from a public Google Sheet on every page load. No build, no package manager, no tests; libraries come from cdnjs (Chart.js, PapaParse, SheetJS loaded upfront; ExcelJS, html2canvas, jsPDF lazy-loaded via the `LIBS` map when a report is generated).

The user's constraint: nothing may be installed — keep it a plain static file deployable on Vercel.

## Source of truth: `Note`

The user edits the dashboard in the local file `Note` (git-ignored). `index.html` is a straight copy of it: when `Note` changes, `cp Note index.html`, then commit and push. Don't hand-edit `index.html` in a way that diverges from `Note` without telling the user.

## Run / deploy

- Preview: open `index.html` in a browser or serve the folder statically. It needs network access to Google Sheets and cdnjs.
- Deploy: Vercel, Framework Preset **Other**, empty build command and output directory; pushing to `main` redeploys. `vercel.json` only sets headers (`X-Robots-Tag: noindex, nofollow`, `nosniff`, `no-referrer`) and `cleanUrls`. If a CSP is ever added, it must allow cdnjs, Google Fonts and `docs.google.com`.

## Architecture of `index.html`

Several `<script>` blocks, in order:
1. View switching (`activateView`) for the left nav: `view-dashboard`, `view-annual`, `view-masterplan`, `view-dgarea` (PA/MOU, grouped by executive).
2. Report generator IIFE (PDF/Excel, A4 landscape): picks fiscal year + month from current data or the history sheet; topics in `TOPICS`.
3. `window.ACPDash` — rendering module; `ACPDash.start({records, strategies, orgKpis, historyPeriods, masterPlans})` draws everything.
4. Google Sheet loader (last block): `GOOGLE_SHEET_ID`, `SHEET_RANGES`, `SHEET_SPECS`, then `loadAndRender()` → `fetchSheetBySpec()` per sheet → `buildDashboardData()` / `buildOrgKpis()` / `buildHistoryDataset()` → `ACPDash.start()`. Errors show `#errorOverlay`.

Loader behaviours worth knowing:
- gviz URLs use `tqx=out:csv&range=…&sheet=<encodeURIComponent(name)>`. If the sheet name doesn't exist (or is mis-encoded), Google silently returns the **first** sheet — that's why every `SHEET_SPECS` entry lists `required` header columns and alternate names, and the loader validates headers. When testing from Git Bash, Thai sheet names can get mangled; percent-encode the UTF-8 bytes yourself or use `gid=`.
- Only the latest `Fiscal_Year` found in the projects sheet is kept.
- `normCode()` re-pads numeric project codes to 6 digits (e.g. `010101`), since leading zeros get lost in Sheets.
- `isYes()` interprets checkbox-like cells (TRUE/Yes/✓/ใช่…) in the `ส่วนงานภายใต้ผู้บริหาร` matrix (rows = owner unit, columns = executive).
- Status levels are Thai strings: `['ดีมาก','ดี','พอใช้','ต้องปรับปรุง']`.

## Files that must stay out of the repo

Per `.gitignore`: `Note`, `ACP/` (source exports), `แดชบอร์ดแผนปฏิบัติการ-กยท-2569.html` (contains staff emails), `*.ps1`, `*.png`, `scratchpad/`, `.vercel`.

## Conventions

- Commit messages are written in Thai.
- UI text is Thai; dates use the Buddhist calendar (2569 = 2026).
