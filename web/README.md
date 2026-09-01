# bromodachi web

Progress dashboard + question management for the bromodachi buddy.
Two users (owner + teacher "sensei"), password login, RLS-gated.

## Local dev

    npm install
    npm run dev        # against the live Supabase project; .env.local has the keys

## Deploy

Vercel, connected to the repo with Root Directory = `web`. Every push to
master deploys. Env vars (already set): NEXT_PUBLIC_SUPABASE_URL,
NEXT_PUBLIC_SUPABASE_ANON_KEY (publishable key - RLS is the gate).

## One-time setup already done (2026-09-01)

- Supabase auth: public signups disabled; two users created via admin API
  (passwords in ~/.config/bromodachi/web-logins.txt on the dev machine).
- allowed_users seeded by migration 20260901120500.
- The teacher types the username "sensei"; the login form maps anything
  without an @ to @bromodachi.local.
