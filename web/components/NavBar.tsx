"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import type { Role } from "@/lib/types";

export function NavBar({ role }: { role: Role }) {
  const [email, setEmail] = useState("");
  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setEmail(data.user?.email ?? ""));
  }, []);
  const shown = email === "sensei@bromodachi.local" ? "sensei" : email;
  return (
    <nav>
      <span className="brand">ブロモダチ</span>
      <Link href="/">Dashboard</Link>
      <Link href="/questions">Questions</Link>
      <span className="spacer" />
      <span className="who">{shown} · {role}</span>
      <button onClick={() => supabase.auth.signOut().then(() => location.assign("/login"))}>
        Sign out
      </button>
    </nav>
  );
}
