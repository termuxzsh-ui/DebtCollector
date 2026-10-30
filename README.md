# DebtCollecter

DebtCollecter is a personal loan and collections workspace built with React, TypeScript, Vite, Tailwind CSS, Supabase, and Netlify. Supabase is the system of record for users, loans, payments, tasks, reminders, notes, profiles, and private attachments. The browser does not use `localStorage` as the primary data store.

## Features

- Supabase email/password sign-up, sign-in, email password reset, session persistence, and password change.
- Borrower directory and profiles with loan totals, payment history, and reminder history.
- Loan creation, search, status filtering, sorting, payment recording, notes, timelines, and private document uploads.
- Payment-derived balances and paid status; overdue status and due-day labels are derived from due dates.
- Planner, completion tracking, recurring task definitions, and database-generated next occurrences.
- Today briefing, collection reminders, upcoming payment lists, calendar, cash-flow charts, portfolio reports, and forecast summaries.
- CSV backup export and borrower CSV import.
- Dark/light appearance, currency preference, responsive navigation, and installable PWA app shell.
- Row-level security on every application table and private per-user Storage paths.

## Requirements

- Node.js 20 or newer and npm.
- A Supabase project (Free Tier works for personal-scale usage).
- A Netlify site for hosted deployment.

## Local setup

1. Create a Supabase project and open **SQL Editor**.
2. Run the entire [`supabase/schema.sql`](supabase/schema.sql) script. It creates all app tables, indexes, update triggers, payment and recurring-task triggers, per-user RLS policies, and the private `loan-attachments` bucket policies.
3. In Supabase **Authentication → URL Configuration**, set the local redirect URL to `http://localhost:5173/**`. Add the production Netlify URL after deployment.
4. Copy `.env` to `.env` and set your project URL and **anon/public** key:

   ```env
   VITE_SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
   VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
   ```

   Never put a Supabase service-role key in frontend code or Netlify environment variables exposed to the build.

5. Install and start the app:

   ```sh
   npm install
   npm run dev
   ```

6. Create an account through the app. If Supabase email confirmation is enabled, confirm the message before signing in.

## Database and security

The schema is intended to be run as a Supabase SQL Editor administrator. Tables are private by default and RLS is enabled for `profiles`, `borrowers`, `loans`, `payments`, `loan_notes`, `loan_timeline`, `attachments`, `tasks`, `task_occurrences`, `recurring_tasks`, `notifications`, and `reminder_logs`.

Every table policy scopes access to `auth.uid()`. Child-table policies additionally verify that the referenced borrower, loan, task, or recurring task belongs to the same authenticated user. The attachment bucket is private; its object policy restricts first-level storage paths to the signed-in user's UUID. The app creates short-lived signed URLs only after an authenticated attachment lookup.

Due and overdue states are evaluated against the current date in the app rather than persisted as a stale scheduled status. A payment trigger updates a loan to `paid` when collected payments cover its principal. A task trigger records completed recurring occurrences and creates the next task transactionally. No server-side email/SMS reminder delivery is configured; the collection center records follow-up actions in-app.

## Netlify deployment

1. Push the project to a Git provider and import it in Netlify.
2. Netlify uses [`netlify.toml`](netlify.toml): build command `npm run build`, publish directory `dist`, and SPA route fallback.
3. In **Site configuration → Environment variables**, add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
4. Deploy, then add your deployed URL to the Supabase Auth redirect allowlist and site URL.
5. Redeploy after changing environment variables.

## PWA and offline behavior

The app has a web manifest, vector app icon, installable standalone display mode, and a service worker that caches the application shell for offline launch. Authenticated records continue to load from Supabase; the current release does not provide offline editing or a locally persisted copy of financial records. The browser cache is deliberately limited to app-shell resources.

## Backup and import

Use **Settings → Backup & export → Export CSV** for a portable report containing borrowers, loans, payments, tasks, and reminder events. The import action adds borrowers from CSV columns `full_name`, `phone`, `email`, `address`, and `notes`; it does not overwrite existing rows. Attachments are stored separately in the private Supabase bucket and are not included in CSV export. Keep an independent Supabase backup for full disaster recovery.

## Seed data example

Create a borrower and loan using the UI to seed a real user workspace. To test CSV borrower import, save this as `borrowers.csv` and use **Settings → Import borrowers CSV**:

```csv
full_name,phone,email,address,notes
Jamie Rivera,+1-555-0101,jamie@example.com,"10 Oak Street","Agreed to monthly installments"
Taylor Chen,+1-555-0102,taylor@example.com,"24 Market Road","Prefers text follow-ups"
```

## Project structure

```text
public/                 PWA manifest, icon, service worker
src/App.tsx             Routes, authenticated workflows, reports, forms
src/lib/supabase.ts     Supabase client configuration
src/styles.css          Responsive dark/light design system
src/types.ts            Domain types
supabase/schema.sql     Tables, indexes, triggers, RLS, Storage policies
netlify.toml            Build and SPA routing configuration
```

## Production notes

- Configure Supabase Auth email templates, SMTP, URL allowlists, and database backups before onboarding real data.
- The client bundle includes public app code only; Supabase RLS is the security boundary. Do not disable RLS.
- Validate backup exports and retention against your privacy requirements. Attachments are limited to 10 MB and PDF/JPG/PNG/WEBP.
- Native browser notifications, scheduled push delivery, email/SMS collection reminders, Excel import/export, and offline financial-record access are not included in this release. In-app collection and task attention badges are derived from current Supabase data.
- Run `npm run build` before deployment.
"# DebtCollector" 
