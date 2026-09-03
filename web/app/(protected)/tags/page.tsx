"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabase } from "@/lib/supabase/client";
import { Bar, Blueprint, Check, Empty, Seg, TrendStrip } from "@/components/ui";
import { aggAll, byDirection, tagAgg, tagsByQuestion, type QAgg, type TagAgg } from "@/lib/agg";
import { directionLabel, fmtMD, fmtPct, fmtSec, localDay, numWord } from "@/lib/format";
import type { Attempt, Lesson, Question, QuestionTag, ReviewSession, SrsState, Tag, TagKind } from "@/lib/types";

// The pattern across every lesson: what to re-teach, rather than which
// lesson went badly. Everything aggregates by tag.
export default function Tags() {
  const [lessons, setLessons] = useState<Lesson[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [aggs, setAggs] = useState<QAgg[] | null>(null);
  const [kind, setKind] = useState<TagKind>("grammar");
  const [selected, setSelected] = useState<string | null>(null);
  const [forReview, setForReview] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [lr, qr, tr, qtr, sr, ar] = await Promise.all([
      supabase.from("lessons").select("*").order("taught_on", { ascending: false }),
      supabase.from("questions").select("*"),
      supabase.from("tags").select("*").order("label_ja"),
      supabase.from("question_tags").select("*"),
      supabase.from("srs_state").select("*"),
      supabase.from("attempts").select("*"),
    ]);
    const err = lr.error ?? qr.error ?? tr.error ?? qtr.error ?? sr.error ?? ar.error;
    if (err) return setError(err.message);
    const allTags = (tr.data ?? []) as Tag[];
    const srs = new Map(((sr.data ?? []) as SrsState[]).map((s) => [s.question_id, s]));
    setLessons(lr.data ?? []);
    setTags(allTags);
    setAggs(aggAll((qr.data ?? []) as Question[], (ar.data ?? []) as Attempt[], srs, tagsByQuestion((qtr.data ?? []) as QuestionTag[], allTags)));
  }, []);
  useEffect(() => { load(); }, [load]);

  const now = useMemo(() => new Date(), []);
  const rows = useMemo<TagAgg[]>(() => {
    if (!aggs) return [];
    return tags
      .filter((t) => t.kind === kind)
      .map((t) => tagAgg(t, aggs.filter((a) => a.tags.some((x) => x.id === t.id)), now))
      .filter((r) => r.questions > 0)
      .sort((a, b) => (a.firstTry ?? 2) - (b.firstTry ?? 2) || b.questions - a.questions);
  }, [aggs, tags, kind, now]);

  const current = rows.find((r) => r.tag.id === selected) ?? rows[0] ?? null;
  const weakest = rows[0] ?? null;
  const weakRows = rows.filter((r) => r.firstTry != null && r.firstTry < 0.8).slice(0, 4);
  const newest = lessons.find((l) => l.active) ?? lessons[0] ?? null;

  async function carry() {
    if (!newest) return;
    setBusy(true);
    const today = localDay(now);
    const { data: existing, error: e1 } = await supabase.from("review_sessions").select("*")
      .eq("lesson_id", newest.id).eq("held_on", today).maybeSingle();
    if (e1) { setBusy(false); return setError(e1.message); }
    const prev = (existing as ReviewSession | null)?.tag_ids ?? [];
    const tag_ids = [...new Set([...prev, ...forReview])];
    const { error } = await supabase.from("review_sessions")
      .upsert({ lesson_id: newest.id, held_on: today, tag_ids }, { onConflict: "lesson_id,held_on" });
    setBusy(false);
    if (error) return setError(error.message);
    setMsg(`Carried ${forReview.size} tag${forReview.size === 1 ? "" : "s"} to the ${fmtMD(newest.taught_on)} review sheet.`);
    setForReview(new Set());
  }

  if (error) return <p className="error" style={{ padding: 34 }}>{error}</p>;
  if (!aggs) return null;

  const totalQ = aggs.length;
  const dirs = current ? byDirection(current.aggs) : [];
  const weakQs = current ? current.aggs.filter((a) => a.tries > 0).sort((a, b) => (a.firstTry ?? 2) - (b.firstTry ?? 2)) : [];
  const interpretation = current ? interpret(current, aggs) : null;
  const allDirs = byDirection(aggs);

  return (
    <div className="page" style={{ gap: 24 }}>
      <div className="row end" style={{ gap: 16 }}>
        <div>
          <h3 style={{ margin: "0 0 4px" }}>Grammar points and kanji</h3>
          <p className="muted head-note">
            Across all {lessons.length} lessons and {totalQ} questions. This is the view that says what to re-teach, rather than which lesson went badly.
          </p>
        </div>
        <span className="spacer" />
        <Seg<TagKind> name="kind" value={kind} onChange={(k) => { setKind(k); setSelected(null); }} options={[
          { value: "grammar", label: "Grammar" }, { value: "kanji", label: "Kanji" }, { value: "vocabulary", label: "Vocabulary" },
        ]} />
      </div>

      <Blueprint className="pad-20">
        <div className="row base">
          <h6 style={{ margin: 0 }}>Weakest tags first</h6>
          <span className="muted tiny">first-try accuracy, questions carrying the tag, and where they live</span>
        </div>
        {rows.length === 0 ? <Empty>No {kind} tags on any question yet — add them in the question editor.</Empty> : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>tag</th><th>questions</th><th>lessons</th><th>first try</th><th>hint use</th><th>to 1st key</th><th>self-corrects</th><th>trend</th></tr></thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.tag.id} onClick={() => setSelected(r.tag.id)} style={{ cursor: "pointer", background: current?.tag.id === r.tag.id ? "color-mix(in srgb, var(--color-accent) 8%, transparent)" : undefined }}>
                    <td><span lang="ja" style={{ fontSize: 15 }}>{r.tag.label_ja}</span>{r.tag.label_en && <span className="muted small"> · {r.tag.label_en}</span>}</td>
                    <td className="mono">{r.questions}</td>
                    <td className="muted small2">{r.lessons} lesson{r.lessons === 1 ? "" : "s"}</td>
                    <td className="mono em">{fmtPct(r.firstTry)}</td>
                    <td className="mono muted">{fmtPct(r.hintRate)}</td>
                    <td className="mono">{fmtSec(r.avgFirstKey)}</td>
                    <td className="mono">{r.selfCorrects}</td>
                    <td><TrendStrip bars={r.trend} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Blueprint>

      <div className="cols-2" style={{ gridTemplateColumns: "1.15fr 1fr" }}>
        <Blueprint className="pad-20">
          {current ? (
            <>
              <div className="row base" style={{ gap: 12 }}>
                <h6 style={{ margin: 0 }}><span lang="ja">{current.tag.label_ja}</span> — the {numWord(current.questions)} question{current.questions === 1 ? "" : "s"}</h6>
                {weakest?.tag.id === current.tag.id && <span className="tag tag-outline">weakest tag</span>}
              </div>
              {weakQs.length === 0 ? <Empty>None of these questions has been asked yet.</Empty> : (
                <table className="table">
                  <thead><tr><th>question</th><th>lesson</th><th>direction</th><th>first try</th><th>most common wrong answer</th></tr></thead>
                  <tbody>
                    {weakQs.map((a) => (
                      <tr key={a.question.id}>
                        <td className="ja" lang="ja"><Link href={`/questions/${a.question.id}`}>{a.question.prompt}</Link></td>
                        <td className="mono muted">{fmtMD(lessons.find((l) => l.id === a.question.lesson_id)?.taught_on ?? "")}</td>
                        <td className="muted small2">{directionLabel(a.question.direction)}</td>
                        <td className="mono">{fmtPct(a.firstTry)}</td>
                        <td className="muted" lang="ja">{a.mostCommonWrong ?? "—"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
              {interpretation && <p className="prose-13" style={{ marginTop: 2 }}>{interpretation}</p>}
            </>
          ) : <Empty>Pick a tag above.</Empty>}
        </Blueprint>

        <div className="stack" style={{ gap: 20 }}>
          <Blueprint className="pad-20">
            <h6 style={{ margin: 0 }}>First-try accuracy by direction</h6>
            {allDirs.length === 0 ? <Empty>Nothing answered yet.</Empty> : (
              <div className="bar-grid" style={{ gridTemplateColumns: "126px 1fr 42px" }}>
                {allDirs.map((d) => (
                  <Frag key={d.key}>
                    <span>{directionLabel(d.key)}</span>
                    <Bar ratio={d.firstTry} />
                    <span className="mono muted n">{fmtPct(d.firstTry)}</span>
                  </Frag>
                ))}
              </div>
            )}
            {directionNote(allDirs)}
          </Blueprint>

          <Blueprint className="pad-20" style={{ gap: 12 }}>
            <h6 style={{ margin: 0 }}>Add to the review sheet</h6>
            {weakRows.length === 0 ? <Empty>No tag is under 80% first-try right now.</Empty> : (
              <div className="check-list" style={{ gap: 9 }}>
                {weakRows.map((r) => (
                  <Check key={r.tag.id} checked={forReview.has(r.tag.id)}
                         onChange={(on) => setForReview((s) => { const n = new Set(s); if (on) n.add(r.tag.id); else n.delete(r.tag.id); return n; })}>
                    Re-teach <span lang="ja">{r.tag.label_ja}</span> — {r.questions} question{r.questions === 1 ? "" : "s"}{r.lessons > 1 && `, ${r.lessons} lessons`}
                  </Check>
                ))}
              </div>
            )}
            <button className="btn btn-primary btn-block" disabled={busy || forReview.size === 0 || !newest} onClick={carry}>
              Carry {forReview.size} tag{forReview.size === 1 ? "" : "s"} to {newest ? `the ${fmtMD(newest.taught_on)} ` : ""}review sheet
            </button>
            {msg && <p className="muted small" style={{ margin: 0 }}>{msg}</p>}
          </Blueprint>
        </div>
      </div>
    </div>
  );
}

// Only stated when unambiguous: every asked question under the tag shares
// one direction, and the same words exist in another direction to compare.
function interpret(t: TagAgg, all: QAgg[]): string | null {
  const asked = t.aggs.filter((a) => a.tries > 0);
  if (asked.length < 2) return null;
  const dirs = new Set(asked.map((a) => a.question.direction));
  if (dirs.size !== 1) return null;
  const dir = asked[0].question.direction;
  const answers = new Set(asked.flatMap((a) => a.question.answers.map((x) => x.toLowerCase())));
  const reverse = all.filter((a) => a.tries > 0 && a.question.direction !== dir && a.question.answers.some((x) => answers.has(x.toLowerCase())));
  const head = `Every asked question here is a ${directionLabel(dir)} prompt.`;
  if (reverse.length === 0) return head;
  const tries = reverse.reduce((s, a) => s + a.tries, 0), correct = reverse.reduce((s, a) => s + a.correct, 0);
  return `${head} The same words in other directions score ${fmtPct(correct / tries)}.`;
}

function directionNote(dirs: { key: string; firstTry: number | null; n: number }[]) {
  const withData = dirs.filter((d) => d.firstTry != null && d.n >= 5);
  if (withData.length < 2) return null;
  const lo = withData[0], hi = withData[withData.length - 1];
  const gap = Math.round(((hi.firstTry as number) - (lo.firstTry as number)) * 100);
  if (gap < 10) return <p className="muted small2" style={{ margin: 0 }}>The directions are within {gap} points of each other.</p>;
  return <p className="muted small2" style={{ margin: 0 }}>{directionLabel(lo.key as never)} trails {directionLabel(hi.key as never)} by {gap} points.</p>;
}

function Frag({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}
