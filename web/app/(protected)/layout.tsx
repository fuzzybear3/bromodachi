"use client";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { NavBar } from "@/components/NavBar";
import type { Role } from "@/lib/types";

// RLS is the real gate; this probe only decides what to render. An authed
// but unlisted account sees the refusal screen (every query would return
// nothing for them anyway).
export default function ProtectedLayout({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<"loading" | "denied" | Role>("loading");

  useEffect(() => {
    supabase
      .from("allowed_users")
      .select("role")
      .maybeSingle()
      .then(({ data }) => setState((data?.role as Role) ?? "denied"));
  }, []);

  if (state === "loading") return null;
  if (state === "denied")
    return (
      <div className="login-wrap">
        <div className="login-box panel">
          <h1>Not authorized</h1>
          <p className="muted">This account isn&apos;t on the allow list.</p>
          <button onClick={() => supabase.auth.signOut().then(() => location.assign("/login"))}>
            Sign out
          </button>
        </div>
      </div>
    );
  return (
    <>
      <NavBar role={state} />
      <main>{children}</main>
    </>
  );
}
