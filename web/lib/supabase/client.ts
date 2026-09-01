import { createBrowserClient } from "@supabase/ssr";

// Every page is a client component; this is the only client in the app.
export const supabase = createBrowserClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);
