"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase/client";

// Two accounts exist and public signups are disabled. The teacher types the
// username "sensei"; anything without an @ maps to the placeholder domain.
export default function Login() {
  const router = useRouter();
  const [who, setWho] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function signIn(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const email = who.includes("@") ? who.trim() : `${who.trim()}@bromodachi.local`;
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      setError("そのログインは合っていません — check the name and password.");
      setBusy(false);
    } else {
      router.push("/");
      router.refresh();
    }
  }

  return (
    <div className="login-wrap">
      <form className="login-box panel" onSubmit={signIn}>
        <h1>ブロモダチ 🐕</h1>
        <label htmlFor="who">Email or username</label>
        <input id="who" type="text" value={who} autoFocus
               onChange={(e) => setWho(e.target.value)} />
        <label htmlFor="pw">Password</label>
        <input id="pw" type="password" value={password}
               onChange={(e) => setPassword(e.target.value)} />
        {error && <p className="error">{error}</p>}
        <p style={{ marginTop: 16 }}>
          <button className="primary" disabled={busy || !who || !password}>
            {busy ? "…" : "Sign in"}
          </button>
        </p>
      </form>
    </div>
  );
}
