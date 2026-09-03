"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase/client";
import { Corners } from "@/components/ui";

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
      <form className="login-box blueprint" onSubmit={signIn}>
        <Corners />
        <div className="card-kicker">japanese training log</div>
        <h3 lang="ja">日本語トレーニング</h3>
        <div className="field">
          <label htmlFor="who">Email or username</label>
          <input id="who" className="input" type="text" value={who} autoFocus
                 onChange={(e) => setWho(e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="pw">Password</label>
          <input id="pw" className="input" type="password" value={password}
                 onChange={(e) => setPassword(e.target.value)} />
        </div>
        {error && <p className="error">{error}</p>}
        <button className="btn btn-primary btn-block" disabled={busy || !who || !password}>
          {busy ? "…" : "Sign in"}
        </button>
      </form>
    </div>
  );
}
