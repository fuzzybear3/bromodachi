"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import type { Role } from "@/lib/types";

// /lessons and /review resolve to the newest active lesson (see their
// page files), so the nav stays static.
const LINKS: { href: string; label: string; match: (p: string) => boolean }[] = [
  { href: "/", label: "Home", match: (p) => p === "/" },
  { href: "/questions", label: "Questions", match: (p) => p.startsWith("/questions") },
  { href: "/lessons", label: "Lesson review", match: (p) => p.startsWith("/lessons") && !p.endsWith("/review") },
  { href: "/tags", label: "Tags", match: (p) => p.startsWith("/tags") },
  { href: "/review", label: "Review sheet", match: (p) => p.endsWith("/review") },
];

export function NavBar({ role }: { role: Role }) {
  const path = usePathname();
  const [email, setEmail] = useState("");
  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setEmail(data.user?.email ?? ""));
  }, []);
  const shown = email === "sensei@bromodachi.local" ? "sensei" : email;
  return (
    <nav className="nav">
      <span className="nav-brand" lang="ja">日本語トレーニング</span>
      {LINKS.map((l) => (
        <Link key={l.href} href={l.href} aria-current={l.match(path) ? "page" : undefined}>{l.label}</Link>
      ))}
      <span className="who">{shown} · {role}</span>
      <button className="link" onClick={() => supabase.auth.signOut().then(() => location.assign("/login"))}>
        Sign out
      </button>
    </nav>
  );
}
