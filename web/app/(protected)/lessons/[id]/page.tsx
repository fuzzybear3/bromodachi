"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase/client";
import { AttemptStrip, Blueprint, Check, Empty, Seg, StatPair } from "@/components/ui";
import { aggAll, lessonSummary, tagsByQuestion, worstFirst, type Mastery, type QAgg } from "@/lib/agg";
import { daysAgo, directionLabel, fmtMD, fmtPct, fmtSec, localDay } from "@/lib/format";
import type { Attempt, Lesson, Question, QuestionTag, ReviewSession, SrsState, Tag } from "@/lib/types";

type Filter = "all" | "notSticking" | "mastered";
type SortKey = "firstTry" | "tries" | "hint" | "firstKey" | "total" | "selfCorr" | "lapses";

// The screen the learner and teacher read together: every question in one
// lesson with the statistics that explain it, and checkboxes to mark what
// to re-teach. Marks persist to today's review session for this lesson.
export default function LessonReview() {
  const { id } = useParams<{ id: string }>();
  const [lessons, setLessons] = useState<Lesson[]>([]);
  const [aggs, setAggs] = useState<QAgg[] | null>(null);
  const [session, setSession] = useState<ReviewSession | null>(null);
  const [marked, setMarked] = useState<Set<string>>(new Set());
  const [filter, setFilter] = useState<Filter>("all");
  const [sortKey, setSortKey] = useState<SortKey>("firstTry");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [lr, qr] = await Promise.all([
      supabase.from("lessons").select("*").order("taught_on", { ascending: false }),
      supabase.from("questions").select("*").eq("lesson_id", id).order("position"),
    ]);
    if (lr.error ?? qr.error) return setError((lr.error ?? qr.error)!.message);
    const questions = (qr.data ?? []) as Question[];
    const ids = questions.map((q) => q.id);
    const [sr, ar, tr, qtr, rs] = await Promise.all([
      supabase.from("srs_state").select("*").in("question_id", ids),
      supabase.from("attempts").select("*").in("question_id", ids),
      supabase.from("tags").select("*"),
      supabase.from("question_tags").select("*").in("question_id", ids),
      supabase.from("review_sessions").select("*").eq("lesson_id", id).eq("held_on", localDay(new Date())).maybeSingle(),
    ]);
    const err = sr.error ?? ar.error ?? tr.error ?? qtr.error ?? rs.error;
    if (err) return setError(err.message);
    const srs = new Map(((sr.data ?? []) as SrsState[]).map((s) => [s.question_id, s]));
    const byQ = tagsByQuestion((qtr.data ?? []) as QuestionTag[], (tr.data ?? []) as Tag[]);
    setLessons(lr.data ?? []);
    setAggs(aggAll(questions, (ar.data ?? []) as Attempt[], srs, byQ));
    const s = rs.data as ReviewSession | null;
    setSession(s);
    setMarked(new Set(s?.marked_question_ids ?? []));
  }, [id]);
  useEffect(() => { load(); }, [load]);

  const lesson = lessons.find((l) => l.id === id) ?? null;
  const summary = useMemo(() => (aggs ? lessonSummary(aggs) : null), [aggs]);
  const rows = useMemo(() => {
    if (!aggs) return [];
    const base = worstFirst(aggs);
    const keyed = sortKey === "firstTry" ? base : [...base].sort((a, b) => sortVal(b, sortKey) - sortVal(a, sortKey));
    const want: Mastery | null = filter === "all" ? null : filter;
    return want ? keyed.filter((r) => r.mastery === want) : keyed;
  }, [aggs, filter, sortKey]);

  async function saveMarks() {
    setSaving(true);
    const row = { lesson_id: id, held_on: localDay(new Date()), marked_question_ids: [...marked] };
    const { data, error } = await supabase.from("review_sessions")
      .upsert(row, { onConflict: "lesson_id,held_on" }).select("*").single();
    setSaving(false);
    if (error) return setError(error.message);
    setSession(data as ReviewSession);
  }

  if (error) return <p className="error" style={{ padding: 34 }}>{error}</p>;
  if (!lesson || !aggs || !summary) return null;

  const dirty = session
    ? !sameSet(marked, new Set(session.marked_question_ids))
    : marked.size > 0;

  return (
    <div className="page tight">
      <div className="row wrap" style={{ gap: 10 }}>
        <span className="card-kicker" style={{ marginRight: 6 }}>lesson</span>
        {lessons.map((l) => (
          <Link key={l.id} href={`/lessons/${l.id}`}
                className={`btn ${l.id === id ? "btn-primary" : l.active ? "btn-secondary" : "btn-ghost"}`}>
            <span className="mono">{fmtMD(l.taught_on)}</span>
            {l.title && <span lang="ja">{l.title}</span>}
          </Link>
        ))}
        <span className="spacer" />
        <Link className="btn btn-secondary" href={`/lessons/${id}/review`}>Open review sheet</Link>
      </div>

      <div className="row end" style={{ gap: 20 }}>
        <div>
          <h3 style={{ margin: "0 0 4px" }}>
            <span className="mono" style={{ fontSize: 23 }}>{lesson.taught_on}</span>
            {lesson.title && <> <span lang="ja">{lesson.title}</span></>}
            {!lesson.active && <span className="muted" style={{ fontSize: 15 }}> · disabled</span>}
          </h3>
          <p className="muted head-note">
            {aggs.length} questions · {summary.answers} answers · taught {daysAgo(lesson.taught_on, new Date())}
          </p>
        </div>
        <span className="spacer" />
        <div className="stat-pairs">
          <StatPair value={fmtPct(summary.firstTry)} label="first try" />
          <StatPair value={summary.avgFirstKey == null ? "—" : (summary.avgFirstKey / 1000).toFixed(1)} unit={summary.avgFirstKey == null ? undefined : "s"} label="to 1st key" />
          <StatPair value={fmtPct(summary.hintRate)} label="hint use" />
          <StatPair value={String(summary.notSticking)} label="not sticking" />
          <StatPair value={String(summary.mastered)} label="mastered" />
        </div>
      </div>

      <div className="row">
        <Seg<Filter> name="filter" value={filter} onChange={setFilter} options={[
          { value: "all", label: `All ${aggs.length}` },
          { value: "notSticking", label: "Not sticking" },
          { value: "mastered", label: "Mastered" },
        ]} />
        <span className="muted small">sorted by {SORT_LABEL[sortKey]}{sortKey !== "firstTry" && " — "}
          {sortKey !== "firstTry" && <a href="#" onClick={(e) => { e.preventDefault(); setSortKey("firstTry"); }}>reset</a>}
        </span>
        <span className="spacer" />
        <span className="muted small">{marked.size} marked to re-teach{session?.applied_at ? " · sheet applied" : ""}</span>
        <button className="btn btn-primary" disabled={!dirty || saving} onClick={saveMarks}>
          {session && !dirty ? "Marks on review sheet" : "Add marked to review sheet"}
        </button>
      </div>

      <Blueprint className="pad-0">
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th style={{ width: 34 }} />
                <th>question</th>
                <th>tags</th>
                <th>direction</th>
                <Th k="tries" cur={sortKey} set={setSortKey}>tries</Th>
                <Th k="firstTry" cur={sortKey} set={setSortKey}>first try</Th>
                <th>last 6</th>
                <Th k="hint" cur={sortKey} set={setSortKey}>hint</Th>
                <Th k="firstKey" cur={sortKey} set={setSortKey}>to 1st key</Th>
                <Th k="total" cur={sortKey} set={setSortKey}>total</Th>
                <Th k="selfCorr" cur={sortKey} set={setSortKey}>self-corr</Th>
                <Th k="lapses" cur={sortKey} set={setSortKey}>lapses</Th>
                <th>most common wrong answer</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && (
                <tr><td colSpan={13}><Empty>{aggs.length === 0 ? "No questions in this lesson yet." : "Nothing in this bucket."}</Empty></td></tr>
              )}
              {rows.map((r) => (
                <tr key={r.question.id} style={r.question.active ? undefined : { opacity: 0.5 }}>
                  <td>
                    <Check checked={marked.has(r.question.id)}
                           onChange={(on) => setMarked((m) => { const n = new Set(m); if (on) n.add(r.question.id); else n.delete(r.question.id); return n; })} />
                  </td>
                  <td className="ja" lang="ja"><Link href={`/questions/${r.question.id}`}>{r.question.prompt}</Link></td>
                  <td><span className="tags">{r.tags.map((t) => <span key={t.id} className="tag tag-accent" lang="ja">{t.label_ja}</span>)}</span></td>
                  <td className="muted dir">{directionLabel(r.question.direction)}</td>
                  <td className="mono">{r.tries}</td>
                  <td className="mono em">{fmtPct(r.firstTry)}</td>
                  <td>{r.last6.length ? <AttemptStrip results={r.last6} /> : <span className="muted">—</span>}</td>
                  <td className="mono muted">{fmtPct(r.hintRate)}</td>
                  <td className="mono">{fmtSec(r.avgFirstKey)}</td>
                  <td className="mono">{fmtSec(r.avgTotal)}</td>
                  <td className="mono">{r.selfCorrected}</td>
                  <td className="mono">{r.lapses}</td>
                  <td className="muted" lang="ja">{r.mostCommonWrong ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Blueprint>
      <div className="muted small">
        Time to first keystroke is recall; total time includes typing. Both count only while the answer box had focus, and skip pops the buddy flagged as stalled.
      </div>
    </div>
  );
}

const SORT_LABEL: Record<SortKey, string> = {
  firstTry: "first-try accuracy", tries: "tries", hint: "hint use", firstKey: "time to first key",
  total: "total time", selfCorr: "self-corrections", lapses: "lapses",
};

function sortVal(r: QAgg, k: SortKey): number {
  switch (k) {
    case "firstTry": return -(r.firstTry ?? 2);
    case "tries": return r.tries;
    case "hint": return r.hintRate ?? -1;
    case "firstKey": return r.avgFirstKey ?? -1;
    case "total": return r.avgTotal ?? -1;
    case "selfCorr": return r.selfCorrected;
    case "lapses": return r.lapses;
  }
}

function Th({ k, cur, set, children }: { k: SortKey; cur: SortKey; set: (k: SortKey) => void; children: React.ReactNode }) {
  return (
    <th className="th-sort" onClick={() => set(k)} style={cur === k ? { color: "var(--color-text)" } : undefined}>
      {children}
    </th>
  );
}

function sameSet(a: Set<string>, b: Set<string>): boolean {
  if (a.size !== b.size) return false;
  for (const x of a) if (!b.has(x)) return false;
  return true;
}
