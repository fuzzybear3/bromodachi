"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase/client";
import { Bar, Blueprint, Check, Empty } from "@/components/ui";
import {
  accuracy, aggAll, byType, dominantPattern, hintRate, lessonSummary, patternSentence,
  tagsByQuestion, worstFirst, type QAgg,
} from "@/lib/agg";
import { fmtMin, fmtPct, fmtSec, localDay, numWord } from "@/lib/format";
import type { Attempt, Lesson, Question, QuestionTag, ReviewSession, SrsState, StagedChange, Tag } from "@/lib/types";

// What the sitting produces: the re-teach list carried from the lesson
// review, the notes typed while talking, and a staged set of changes that
// touch nothing until Apply. Apply is one RPC, one transaction.
export default function ReviewSheet() {
  const { id } = useParams<{ id: string }>();
  const [lesson, setLesson] = useState<Lesson | null>(null);
  const [aggs, setAggs] = useState<QAgg[] | null>(null);
  const [tags, setTags] = useState<Tag[]>([]);
  const [recent, setRecent] = useState<Attempt[]>([]); // all lessons, 30d, for the comparison
  const [session, setSession] = useState<ReviewSession | null>(null);
  const [previous, setPrevious] = useState<ReviewSession | null>(null);
  const [note, setNote] = useState("");
  const [staged, setStaged] = useState<StagedChange[]>([]);
  const [busy, setBusy] = useState<"" | "note" | "apply">("");
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const today = localDay(new Date());

  const load = useCallback(async () => {
    const [lr, qr, tr] = await Promise.all([
      supabase.from("lessons").select("*").eq("id", id).maybeSingle(),
      supabase.from("questions").select("*").eq("lesson_id", id).order("position"),
      supabase.from("tags").select("*"),
    ]);
    if (lr.error ?? qr.error ?? tr.error) return setError((lr.error ?? qr.error ?? tr.error)!.message);
    const questions = (qr.data ?? []) as Question[];
    const ids = questions.map((q) => q.id);
    const cutoff = new Date(Date.now() - 30 * 86400_000).toISOString();
    const [sr, ar, qtr, rs, rr] = await Promise.all([
      supabase.from("srs_state").select("*").in("question_id", ids),
      supabase.from("attempts").select("*").in("question_id", ids),
      supabase.from("question_tags").select("*").in("question_id", ids),
      supabase.from("review_sessions").select("*").eq("lesson_id", id).order("held_on", { ascending: false }).limit(5),
      supabase.from("attempts").select("*").gte("answered_at", cutoff),
    ]);
    const err = sr.error ?? ar.error ?? qtr.error ?? rs.error ?? rr.error;
    if (err) return setError(err.message);
    const srs = new Map(((sr.data ?? []) as SrsState[]).map((s) => [s.question_id, s]));
    const allTags = (tr.data ?? []) as Tag[];
    setTags(allTags);
    setLesson(lr.data as Lesson | null);
    setAggs(aggAll(questions, (ar.data ?? []) as Attempt[], srs, tagsByQuestion((qtr.data ?? []) as QuestionTag[], allTags)));
    setRecent((rr.data ?? []) as Attempt[]);
    const sessions = (rs.data ?? []) as ReviewSession[];
    const cur = sessions.find((s) => s.held_on === today) ?? null;
    setSession(cur);
    setPrevious(sessions.find((s) => s.held_on !== today && s.note.trim()) ?? null);
    setNote(cur?.note ?? "");
    setStaged(cur?.staged_changes ?? []);
  }, [id, today]);
  useEffect(() => { load(); }, [load]);

  const summary = useMemo(() => (aggs ? lessonSummary(aggs) : null), [aggs]);
  const marked = useMemo(() => {
    if (!aggs || !session) return [];
    const set = new Set(session.marked_question_ids);
    return worstFirst(aggs.filter((a) => set.has(a.question.id)));
  }, [aggs, session]);
  const carriedTags = useMemo(() => (session?.tag_ids ?? []).map((t) => tags.find((x) => x.id === t)).filter((t): t is Tag => !!t), [session, tags]);

  // The proposals: one "reset" per marked question (grouped into a single
  // checkbox), one "retire" per mastered question. Anything already staged
  // keeps its enabled flag; new proposals arrive unchecked except the reset.
  const proposals = useMemo<StagedChange[]>(() => {
    if (!aggs) return [];
    const prev = new Map(staged.map((c) => [`${c.kind}:${c.target_id}`, c.enabled]));
    const out: StagedChange[] = [];
    for (const a of marked) out.push({ kind: "reset", target_id: a.question.id, enabled: prev.get(`reset:${a.question.id}`) ?? true });
    for (const a of aggs.filter((x) => x.mastery === "mastered" && x.question.active))
      out.push({ kind: "retire", target_id: a.question.id, enabled: prev.get(`retire:${a.question.id}`) ?? false });
    return out;
  }, [aggs, marked, staged]);

  const applied = !!session?.applied_at;
  const enabledCount = proposals.filter((c) => c.enabled).length;

  function setKind(kind: "reset", on: boolean): void;
  function setKind(kind: "retire", on: boolean, target: string): void;
  function setKind(kind: "reset" | "retire", on: boolean, target?: string) {
    setStaged(proposals.map((c) => (c.kind === kind && (target == null || c.target_id === target) ? { ...c, enabled: on } : c)));
  }

  async function upsert(patch: Partial<ReviewSession>): Promise<ReviewSession | null> {
    const row = { lesson_id: id, held_on: today, ...patch };
    const { data, error } = await supabase.from("review_sessions")
      .upsert(row, { onConflict: "lesson_id,held_on" }).select("*").single();
    if (error) { setError(error.message); return null; }
    setSession(data as ReviewSession);
    return data as ReviewSession;
  }

  async function saveNote() {
    setBusy("note");
    await upsert({ note });
    setBusy("");
  }

  async function apply() {
    if (!confirm(`Apply ${enabledCount} change${enabledCount === 1 ? "" : "s"} now? Resets restart a question from unseen (history kept); retirements deactivate the question.`)) return;
    setBusy("apply");
    const s = await upsert({ note, staged_changes: proposals });
    if (!s) return setBusy("");
    const { data, error } = await supabase.rpc("apply_review_session", { session_id: s.id });
    setBusy("");
    if (error) return setError(error.message);
    const r = data as { reset?: number; retired?: number; already_applied?: boolean };
    setMsg(r.already_applied ? "This sheet was already applied." : `Applied: ${r.reset ?? 0} reset, ${r.retired ?? 0} retired.`);
    load();
  }

  if (error) return <p className="error" style={{ padding: 34 }}>{error}</p>;
  if (!lesson || !aggs || !summary) return null;

  const total = aggs.length || 1;
  const types = byType(aggs);
  const acc30 = accuracy(recent), hint30 = hintRate(recent);
  const patterns = marked.map((a) => ({ a, p: dominantPattern(a) })).filter((x) => x.p);
  const days = summary.firstDay && summary.lastDay
    ? Math.max(1, Math.round((new Date(summary.lastDay).getTime() - new Date(summary.firstDay).getTime()) / 86400_000) + 1)
    : 0;
  const worstType = types[0] && types.length > 1 && summary.firstTry != null && (types[0].firstTry ?? 1) < summary.firstTry - 0.05 ? types[0] : null;

  return (
    <div className="page" style={{ padding: "28px 34px 38px", display: "grid", gridTemplateColumns: "1fr 350px", gap: 28, alignItems: "start" }}>
      <div className="stack" style={{ gap: 24 }}>
        <div className="row end hr-rule" style={{ gap: 16 }}>
          <div>
            <div className="card-kicker">review sheet · session of {today}</div>
            <h3 style={{ margin: "2px 0 0" }}>
              <span className="mono" style={{ fontSize: 23 }}>{lesson.taught_on}</span>
              {lesson.title && <> <span lang="ja">{lesson.title}</span></>}
            </h3>
          </div>
          <span className="spacer" />
          {applied
            ? <span className="muted small">applied {new Date(session!.applied_at!).toLocaleString()}</span>
            : <button className="btn btn-primary" disabled={busy !== "" || enabledCount === 0} onClick={apply}>
                Apply {enabledCount} change{enabledCount === 1 ? "" : "s"}
              </button>}
        </div>
        {msg && <p className="muted small" style={{ margin: 0 }}>{msg}</p>}

        <div className="cols-2" style={{ gridTemplateColumns: "1.2fr 1fr", gap: 26 }}>
          <div className="stack">
            <h6 style={{ margin: 0 }}>Where the lesson stands</h6>
            <div className="stacked">
              <span style={{ width: `${(summary.mastered / total) * 100}%` }} />
              <span style={{ width: `${(summary.learning / total) * 100}%` }} />
              <span style={{ width: `${(summary.notSticking / total) * 100}%` }} />
            </div>
            <div className="legend-3">
              <span><span className="mono">{summary.mastered}</span><br /><span className="muted">mastered</span></span>
              <span><span className="mono">{summary.learning}</span><br /><span className="muted">learning</span></span>
              <span><span className="mono">{summary.notSticking}</span><br /><span className="muted">not sticking</span></span>
            </div>
            <p className="prose" style={{ marginTop: 6 }}>
              {summary.answers === 0 ? "No answers recorded for this lesson yet." : (
                <>
                  {summary.answers} answers over {numWord(days)} day{days === 1 ? "" : "s"} at {fmtPct(summary.firstTry)} correct.
                  {acc30 != null && summary.firstTry != null && (
                    <> This lesson {summary.firstTry < acc30 - 0.005 ? "trails" : summary.firstTry > acc30 + 0.005 ? "beats" : "matches"} the 30-day average of {fmtPct(acc30)}
                      {hint30 != null && summary.hintRate != null && <>, and hint use runs {fmtPct(summary.hintRate)} against {fmtPct(hint30)}</>}.</>
                  )}
                  {worstType && <> The gap sits mostly in the {worstType.key} prompts.</>}
                </>
              )}
            </p>
          </div>
          <Blueprint className="pad-18">
            <h6 style={{ margin: 0 }}>By question type</h6>
            {types.length === 0 ? <Empty>Nothing answered yet.</Empty> : (
              <div className="bar-grid" style={{ gridTemplateColumns: "74px 1fr 42px", gap: "9px 10px" }}>
                {types.map((t) => (
                  <Frag key={t.key}>
                    <span>{t.key}</span>
                    <Bar ratio={t.firstTry} className="h10" />
                    <span className="mono muted n">{fmtPct(t.firstTry)}</span>
                  </Frag>
                ))}
              </div>
            )}
          </Blueprint>
        </div>

        <div className="stack">
          <div className="row base" style={{ gap: 12 }}>
            <h6 style={{ margin: 0 }}>Marked to re-teach</h6>
            <span className="muted small">carried from the <Link href={`/lessons/${id}`}>lesson review</Link></span>
          </div>
          {marked.length === 0 && carriedTags.length === 0 ? (
            <Empty>Nothing marked yet — tick questions on the lesson review and press “Add marked to review sheet”.</Empty>
          ) : (
            <div className="table-wrap">
              <table className="table">
                <thead><tr><th>question</th><th>type</th><th>tries</th><th>first try</th><th>hint use</th><th>to 1st key</th><th>lapses</th><th>most common wrong answer</th></tr></thead>
                <tbody>
                  {marked.map((r) => (
                    <tr key={r.question.id}>
                      <td className="ja" lang="ja"><Link href={`/questions/${r.question.id}`}>{r.question.prompt}</Link></td>
                      <td className="muted">{r.question.type}</td>
                      <td className="mono">{r.tries}</td>
                      <td className="mono">{fmtPct(r.firstTry)}</td>
                      <td className="mono muted">{fmtPct(r.hintRate)}</td>
                      <td className="mono">{fmtSec(r.avgFirstKey)}</td>
                      <td className="mono">{r.lapses}</td>
                      <td className="muted" lang="ja">{r.mostCommonWrong ?? "—"}</td>
                    </tr>
                  ))}
                  {carriedTags.map((t) => (
                    <tr key={t.id}>
                      <td colSpan={8}>
                        <span className="tag tag-accent" lang="ja">{t.label_ja}</span>
                        <span className="muted small"> · re-teach this tag{t.label_en ? ` (${t.label_en})` : ""} — carried from <Link href="/tags">Tags</Link></span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        <Blueprint className="pad-18" style={{ gap: 10 }}>
          <h6 style={{ margin: 0 }}>Patterns worth a word</h6>
          {patterns.length === 0
            ? <Empty>No single pattern accounts for the misses on the marked questions yet.</Empty>
            : <p className="prose">{patterns.map(({ a, p }, i) => (
                <span key={a.question.id}>{i > 0 && " "}<span lang="ja">{a.question.prompt}</span>: {patternSentence(p!).replace(/^./, (c) => c.toLowerCase())}</span>
              ))}</p>}
        </Blueprint>
      </div>

      <div className="stack" style={{ gap: 20 }}>
        <Blueprint className="pad-18">
          <h6 style={{ margin: 0 }}>Session notes</h6>
          <div className="field">
            <label>typed while we talked</label>
            <textarea className="input" lang="ja" rows={7} value={note} onChange={(e) => setNote(e.target.value)}
                      onBlur={() => { if (session && note !== session.note) saveNote(); }} />
          </div>
          <button className="btn btn-secondary btn-block" disabled={busy !== "" || note === (session?.note ?? "")} onClick={saveNote}>
            {busy === "note" ? "Saving…" : note === (session?.note ?? "") && session ? "Saved" : "Save note"}
          </button>
          {previous && (
            <>
              <div className="card-meta"><span className="mono">{previous.held_on}</span><span>·</span><span>previous session note</span></div>
              <p className="muted small2" style={{ margin: 0, whiteSpace: "pre-wrap" }} lang="ja">{previous.note}</p>
            </>
          )}
        </Blueprint>

        <Blueprint className="pad-18">
          <h6 style={{ margin: 0 }}>Changes to what the app asks</h6>
          {proposals.length === 0 ? <Empty>Nothing to change: mark questions to re-teach, or wait for one to reach mastered.</Empty> : (
            <div className="check-list">
              {marked.length > 0 && (
                <Check disabled={applied} checked={proposals.some((c) => c.kind === "reset" && c.enabled)} onChange={(on) => setKind("reset", on)}>
                  Reset the {marked.length} marked question{marked.length === 1 ? "" : "s"} to day one
                </Check>
              )}
              {proposals.filter((c) => c.kind === "retire").map((c) => {
                const a = aggs.find((x) => x.question.id === c.target_id)!;
                return (
                  <Check key={c.target_id} disabled={applied} checked={c.enabled} onChange={(on) => setKind("retire", on, c.target_id)}>
                    Retire <span lang="ja">{a.question.prompt}</span> — mastered, {fmtMin(a.srs?.interval_min ?? 0)} interval
                  </Check>
                );
              })}
            </div>
          )}
          <div className="muted small">Nothing changes until you press Apply.{" "}Anything the app can’t do itself — new questions, a different order — goes in the note for sensei.</div>
        </Blueprint>
      </div>
    </div>
  );
}

function Frag({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}
