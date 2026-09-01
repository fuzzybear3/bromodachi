"use client";
import { useCallback, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase/client";
import { perQuestionStats, type QuestionStats } from "@/lib/stats";
import { fmtDur, fmtMin } from "@/lib/format";
import type { Attempt, Lesson, Question, SrsState } from "@/lib/types";

// One lesson's set of words, trouble first: which of them are sticking,
// which are eating time, which lean on the hint.
export default function LessonDetail() {
  const { id } = useParams<{ id: string }>();
  const [lesson, setLesson] = useState<Lesson | null>(null);
  const [rows, setRows] = useState<QuestionStats[]>([]);
  const [summary, setSummary] = useState({ answers: 0, correct: 0, activeMs: 0 });
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const lr = await supabase.from("lessons").select("*").eq("id", id).maybeSingle();
    const qr = await supabase.from("questions").select("*").eq("lesson_id", id).order("position");
    if (lr.error ?? qr.error) return setError((lr.error ?? qr.error)!.message);
    const questions = (qr.data ?? []) as Question[];
    const ids = questions.map((q) => q.id);
    const [sr, ar] = await Promise.all([
      supabase.from("srs_state").select("*").in("question_id", ids),
      supabase.from("attempts").select("*").in("question_id", ids),
    ]);
    if (sr.error ?? ar.error) return setError((sr.error ?? ar.error)!.message);
    const attempts = (ar.data ?? []) as Attempt[];
    const srs = new Map(((sr.data ?? []) as SrsState[]).map((s) => [s.question_id, s]));
    setLesson(lr.data as Lesson);
    setRows(perQuestionStats(questions, attempts, srs));
    setSummary({
      answers: attempts.length,
      correct: attempts.filter((a) => a.correct).length,
      activeMs: attempts.reduce((s, a) => s + (a.active_ms ?? 0), 0),
    });
  }, [id]);
  useEffect(() => { load(); }, [load]);

  if (error) return <p className="error">{error}</p>;
  if (!lesson) return null;

  return (
    <>
      <div className="panel">
        <h2>
          {lesson.taught_on}
          {lesson.title ? <span lang="ja"> · {lesson.title}</span> : null}
          {!lesson.active && <span className="muted"> · disabled</span>}
        </h2>
        <p className="muted">
          {rows.length} questions · {summary.answers} answers
          {summary.answers > 0 && <> · {Math.round((summary.correct / summary.answers) * 100)}% accuracy</>}
          {summary.activeMs > 0 && <> · {fmtDur(summary.activeMs)} studied</>}
        </p>
      </div>
      <div className="panel">
        <h2>Words, trouble first</h2>
        <table>
          <thead>
            <tr><th>question</th><th>type</th><th>tries</th><th>acc</th><th>hint</th>
                <th>avg time</th><th>ease</th><th>lapses</th><th>next due</th></tr>
          </thead>
          <tbody>
            {rows.map(({ question: q, tries, correct, hintUsed, avgActiveMs, srs }) => (
              <tr key={q.id} className={q.active ? "" : "muted"}>
                <td lang="ja"><Link href={`/questions/${q.id}`}>{q.prompt}</Link></td>
                <td className="muted">{q.type}</td>
                <td>{tries}</td>
                <td className={tries && correct / tries < 0.6 ? "miss" : ""}>
                  {tries ? `${Math.round((correct / tries) * 100)}%` : "—"}
                </td>
                <td className="muted">{tries ? `${Math.round((hintUsed / tries) * 100)}%` : "—"}</td>
                <td>{avgActiveMs == null ? "—" : fmtDur(avgActiveMs)}</td>
                <td className="muted">{srs ? srs.ease.toFixed(2) : "—"}</td>
                <td className={srs && srs.lapses > 1 ? "miss" : "muted"}>{srs?.lapses ?? "—"}</td>
                <td className="muted">{srs ? fmtMin((new Date(srs.due_at).getTime() - Date.now()) / 60000) : "unseen"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
