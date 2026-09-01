"use client";
import { useCallback, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { supabase } from "@/lib/supabase/client";
import { QuestionEditor } from "@/components/QuestionEditor";
import { msPerChar, vsOwnMedian } from "@/lib/stats";
import type { Attempt, Lesson, Question, SrsState } from "@/lib/types";

// "Why do I keep missing this word": one question's SRS state and its
// last 50 attempts, with the read-time-scaled speed metrics.
export default function QuestionDetail() {
  const { id } = useParams<{ id: string }>();
  const [q, setQ] = useState<Question | null>(null);
  const [lessons, setLessons] = useState<Lesson[]>([]);
  const [srs, setSrs] = useState<SrsState | null>(null);
  const [attempts, setAttempts] = useState<Attempt[]>([]);
  const [editing, setEditing] = useState(false);
  const [missesOnly, setMissesOnly] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    Promise.all([
      supabase.from("questions").select("*").eq("id", id).maybeSingle(),
      supabase.from("lessons").select("*").order("taught_on", { ascending: false }),
      supabase.from("srs_state").select("*").eq("question_id", id).maybeSingle(),
      supabase.from("attempts").select("*").eq("question_id", id)
        .order("answered_at", { ascending: false }).limit(50),
    ]).then(([qr, lr, sr, ar]) => {
      const err = qr.error ?? lr.error ?? sr.error ?? ar.error;
      if (err) return setError(err.message);
      setQ(qr.data as Question | null);
      setLessons(lr.data ?? []);
      setSrs(sr.data as SrsState | null);
      setAttempts((ar.data ?? []) as Attempt[]);
    });
  }, [id]);
  useEffect(load, [load]);

  if (error) return <p className="error">{error}</p>;
  if (!q) return null;

  const correct = attempts.filter((a) => a.correct).length;

  return (
    <>
      <div className="panel">
        <h2 lang="ja">{q.prompt}</h2>
        <p className="chips">
          {q.answers.map((a) => <span className="chip" lang="ja" key={a}>{a}</span>)}
        </p>
        {q.hint && <p lang="ja" className="muted">ヒント: {q.hint}</p>}
        <p className="muted">
          {q.type} · {q.active ? "active" : "inactive"} ·{" "}
          {correct}/{attempts.length} correct in the last {attempts.length} attempts
        </p>
        <button onClick={() => setEditing(true)}>Edit</button>
      </div>

      <div className="panel">
        <h2>Spaced repetition</h2>
        {srs ? (
          <table>
            <tbody>
              <tr><td className="muted">next due</td><td>{new Date(srs.due_at).toLocaleString()}</td></tr>
              <tr><td className="muted">interval</td><td>{humanMin(srs.interval_min)}</td></tr>
              <tr><td className="muted">ease</td><td>{srs.ease.toFixed(2)}</td></tr>
              <tr><td className="muted">correct in a row</td><td>{srs.reps}</td></tr>
              <tr><td className="muted">lapses</td><td>{srs.lapses}</td></tr>
            </tbody>
          </table>
        ) : (
          <p className="muted">Never answered yet.</p>
        )}
      </div>

      <div className="panel">
        <h2 style={{ display: "flex", alignItems: "center" }}>
          History
          <span style={{ flex: 1 }} />
          <label style={{ display: "flex", gap: 6, alignItems: "center", margin: 0, fontWeight: 400 }}>
            <input type="checkbox" style={{ width: "auto" }} checked={missesOnly}
                   onChange={(e) => setMissesOnly(e.target.checked)} />
            misses only
          </label>
        </h2>
        {attempts.length === 0 ? (
          <p className="muted">No attempts yet.</p>
        ) : (
          <table>
            <thead>
              <tr><th></th><th>Typed</th><th>Hint</th><th>Active time</th>
                  <th>ms/char</th><th>vs usual</th><th>When</th></tr>
            </thead>
            <tbody>
              {attempts.filter((a) => !missesOnly || !a.correct).map((a) => {
                const mpc = msPerChar(a, q);
                const rel = vsOwnMedian(a, attempts);
                return (
                  <tr key={a.id}>
                    <td className={a.correct ? "ok" : "miss"}>{a.correct ? "○" : "×"}</td>
                    <td lang="ja">{a.typed || "—"}</td>
                    <td className="muted">{a.hint_used ? "used" : ""}</td>
                    <td>{a.active_ms == null ? "—" : `${(a.active_ms / 1000).toFixed(1)}s`}</td>
                    <td className="muted">{mpc == null ? "—" : Math.round(mpc)}</td>
                    <td className="muted">{rel == null ? "—" : `${rel.toFixed(1)}×`}</td>
                    <td className="muted">{new Date(a.answered_at).toLocaleString()}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {editing && (
        <QuestionEditor
          question={q}
          lessons={lessons}
          defaultLessonId={q.lesson_id}
          maxPosition={() => q.position}
          onClose={(saved) => {
            setEditing(false);
            if (saved) load();
          }}
        />
      )}
    </>
  );
}

function humanMin(min: number): string {
  if (min < 60) return `${Math.round(min)} min`;
  if (min < 1440) return `${(min / 60).toFixed(1)} h`;
  return `${(min / 1440).toFixed(1)} days`;
}
