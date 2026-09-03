"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabase } from "@/lib/supabase/client";
import { QuestionEditor } from "@/components/QuestionEditor";
import { Blueprint, Corners, Empty, StatPair } from "@/components/ui";
import {
  accuracy, aggAll, dayStreak, dueCount, groupBy, sessions, since, tagsByQuestion, weekColumns,
} from "@/lib/agg";
import { fmtDur, fmtMD, fmtPct, fmtSec, fmtWhen } from "@/lib/format";
import type { Attempt, Lesson, Question, QuestionTag, SrsState, Tag } from "@/lib/types";

// The learner's landing screen: how practice is trending, which lessons
// need attention, what happened recently.
export default function Home() {
  const [lessons, setLessons] = useState<Lesson[]>([]);
  const [questions, setQuestions] = useState<Question[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [links, setLinks] = useState<QuestionTag[]>([]);
  const [srs, setSrs] = useState<Map<string, SrsState>>(new Map());
  const [attempts, setAttempts] = useState<Attempt[] | null>(null);
  const [query, setQuery] = useState("");
  const [editing, setEditing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [lr, qr, tr, qtr, sr, ar] = await Promise.all([
      supabase.from("lessons").select("*").order("taught_on", { ascending: false }),
      supabase.from("questions").select("*"),
      supabase.from("tags").select("*"),
      supabase.from("question_tags").select("*"),
      supabase.from("srs_state").select("*"),
      supabase.from("attempts").select("*").order("answered_at"),
    ]);
    const err = lr.error ?? qr.error ?? tr.error ?? qtr.error ?? sr.error ?? ar.error;
    if (err) return setError(err.message);
    setLessons(lr.data ?? []);
    setQuestions((qr.data ?? []) as Question[]);
    setTags((tr.data ?? []) as Tag[]);
    setLinks((qtr.data ?? []) as QuestionTag[]);
    setSrs(new Map(((sr.data ?? []) as SrsState[]).map((s) => [s.question_id, s])));
    setAttempts((ar.data ?? []) as Attempt[]);
  }, []);
  useEffect(() => { load(); }, [load]);

  const now = new Date();
  const aggs = useMemo(() => (attempts ? aggAll(questions, attempts, srs, tagsByQuestion(links, tags)) : []), [attempts, questions, srs, links, tags]);

  async function enable(l: Lesson) {
    const { error } = await supabase.from("lessons").update({ active: true }).eq("id", l.id);
    if (error) return setError(error.message);
    load();
  }

  if (error) return <p className="error" style={{ padding: 34 }}>{error}</p>;
  if (!attempts) return null;

  const enabled = new Set(lessons.filter((l) => l.active).map((l) => l.id));
  const askable = questions.filter((q) => enabled.has(q.lesson_id));
  const last30 = since(attempts, 30, now);
  const qById = new Map(questions.map((q) => [q.id, q]));
  const lessonById = new Map(lessons.map((l) => [l.id, l]));
  const weeks = weekColumns(attempts, 12, now);
  const busiest = Math.max(1, ...weeks.map((w) => w.answers));
  const byLesson = groupBy(aggs, (a) => a.question.lesson_id);
  const cards = lessons.map((l) => {
    const as = byLesson.get(l.id) ?? [];
    const tries = as.reduce((s, a) => s + a.tries, 0), correct = as.reduce((s, a) => s + a.correct, 0);
    return {
      lesson: l,
      total: as.length,
      mastered: as.filter((a) => a.mastery === "mastered").length,
      notSticking: as.filter((a) => a.mastery === "notSticking").length,
      acc: tries ? correct / tries : null,
      due: dueCount(as.map((a) => a.question), srs, now),
    };
  });
  const troubled = cards.filter((c) => c.lesson.active).sort((a, b) => b.notSticking - a.notSticking)[0];
  const newest = lessons.find((l) => l.active) ?? lessons[0];
  const log = sessions(attempts, qById, lessonById).slice(0, 8);
  const hits = query.trim()
    ? questions.filter((q) => {
        const n = query.trim().toLowerCase();
        return q.prompt.toLowerCase().includes(n) || q.answers.some((a) => a.toLowerCase().includes(n));
      }).slice(0, 8)
    : [];

  return (
    <>
      <div className="band blueprint">
        <Corners />
        <div>
          <div className="card-kicker">japanese training log</div>
          <div className="brand" lang="ja">日本語トレーニング</div>
        </div>
        <span className="spacer" />
        <div className="stat-pairs">
          <StatPair value={String(dueCount(askable, srs, now))} label="due" size={30} />
          <StatPair value={fmtPct(accuracy(last30))} label="accuracy" size={30} />
          <StatPair value={String(dayStreak(attempts, now))} label="streak" size={30} />
          {newest && <Link className="btn btn-primary btn-paper" href={`/lessons/${newest.id}`}>Start review</Link>}
        </div>
      </div>

      <div className="page" style={{ padding: "28px 34px 38px", gap: 26 }}>
        <Blueprint className="pad-20" style={{ gap: 16 }}>
          <div className="row base">
            <h6 style={{ margin: 0 }}>Twelve weeks of practice</h6>
            <span className="muted tiny">column height = answers, fill = accuracy</span>
          </div>
          <div className="weeks">
            {weeks.map((w) => (
              <span key={w.weekStart} style={{ height: `${Math.max(w.answers ? 4 : 0, (w.answers / busiest) * 100)}%`, visibility: w.answers ? "visible" : "hidden" }}
                    title={`${w.answers} answers · ${fmtPct(w.answers ? w.correct / w.answers : null)}`}>
                <i style={{ height: `${w.answers ? (w.correct / w.answers) * 100 : 0}%` }} />
              </span>
            ))}
          </div>
          <div className="weeks-labels mono muted">
            {weeks.map((w) => <span key={w.weekStart}>{fmtMD(w.weekStart)}</span>)}
          </div>
        </Blueprint>

        <div className="row end" style={{ gap: 16 }}>
          <h4 style={{ margin: 0 }}>Lessons</h4>
          <span className="tag tag-neutral">{lessons.length} lessons · {questions.length} questions</span>
          <span className="spacer" />
          <div className="field" style={{ width: 220, position: "relative" }}>
            <input className="input" type="text" lang="ja" placeholder="Search prompt or reading" value={query} onChange={(e) => setQuery(e.target.value)} />
          </div>
          <button className="btn btn-primary" onClick={() => setEditing(true)}>+ New question</button>
        </div>
        {query.trim() && (
          <Blueprint className="pad-14">
            {hits.length === 0 ? <Empty>No question matches “{query}”.</Empty> : (
              <div className="result-list">
                {hits.map((q) => (
                  <span key={q.id}>
                    <Link href={`/questions/${q.id}`} lang="ja">{q.prompt}</Link>
                    <span className="muted small"> · <span lang="ja">{q.answers[0]}</span> · {fmtMD(lessonById.get(q.lesson_id)?.taught_on ?? "")}</span>
                  </span>
                ))}
              </div>
            )}
          </Blueprint>
        )}

        {cards.length === 0 ? <Empty>No lessons yet.</Empty> : (
          <div className="grid-4">
            {cards.map((c) => (
              <Blueprint key={c.lesson.id} className={`pad-18${c.lesson.active ? "" : " dim"}`}>
                <div className="card-kicker">
                  {c.lesson.taught_on}{c.lesson.id === newest?.id && c.lesson.active ? " · newest" : ""}{c.lesson.active ? "" : " · disabled"}
                </div>
                <div className="card-title" lang="ja">{c.lesson.title ?? " "}</div>
                <span className="bar h9"><span style={{ width: `${c.total ? (c.mastered / c.total) * 100 : 0}%` }} /></span>
                <div className="mono muted small">{c.mastered}/{c.total} mastered · {fmtPct(c.acc)} acc</div>
                <div className={`mono small${c.notSticking ? "" : " muted"}`}>
                  {c.notSticking ? `${c.notSticking} not sticking` : c.lesson.active ? (c.due ? `${c.due} due` : "none due") : "none due"}
                </div>
                <div className="row" style={{ gap: 8, marginTop: 2 }}>
                  {c.lesson.active
                    ? <Link className={`btn ${troubled?.lesson.id === c.lesson.id && c.notSticking > 0 ? "btn-primary" : "btn-secondary"}`} href={`/lessons/${c.lesson.id}`}>Review with sensei</Link>
                    : <button className="btn btn-secondary" onClick={() => enable(c.lesson)}>Enable lesson</button>}
                </div>
              </Blueprint>
            ))}
          </div>
        )}

        <Blueprint className="pad-20">
          <h6 style={{ margin: 0 }}>Session log</h6>
          {log.length === 0 ? <Empty>No answers recorded yet.</Empty> : (
            <table className="table">
              <thead><tr><th>when</th><th>lesson</th><th>answers</th><th>accuracy</th><th>hint use</th><th>active time</th><th>avg answer</th></tr></thead>
              <tbody>
                {log.map((s) => (
                  <tr key={s.startedAt}>
                    <td className="mono">{fmtWhen(s.startedAt)}</td>
                    <td lang="ja">{s.lesson ? <Link href={`/lessons/${s.lesson.id}`}>{s.lesson.title ?? s.lesson.taught_on}</Link> : "—"}</td>
                    <td className="mono">{s.answers}</td>
                    <td className="mono">{fmtPct(s.correct / s.answers)}</td>
                    <td className="mono muted">{fmtPct(s.hintUsed / s.answers)}</td>
                    <td className="mono">{fmtDur(s.activeMs)}</td>
                    <td className="mono">{fmtSec(s.avgMs)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Blueprint>
      </div>

      {editing && newest && (
        <QuestionEditor
          question={null}
          lessons={lessons}
          tags={tags}
          questionTagIds={[]}
          defaultLessonId={newest.id}
          maxPosition={(lid) => Math.max(-1, ...questions.filter((q) => q.lesson_id === lid).map((q) => q.position))}
          onClose={(saved) => { setEditing(false); if (saved) load(); }}
        />
      )}
    </>
  );
}
