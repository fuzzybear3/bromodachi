"use client";
import { useCallback, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase/client";
import { QuestionEditor } from "@/components/QuestionEditor";
import { DiffText } from "@/components/DiffText";
import { Blueprint, Empty, StatCard } from "@/components/ui";
import { dominantPattern, expectedFor, patternSentence, questionAgg, type QAgg } from "@/lib/agg";
import { normalize } from "@/lib/diff";
import { cap, directionLabel, fmtPct, fmtSec, fmtWhen, numWord } from "@/lib/format";
import type { Attempt, Lesson, Question, QuestionTag, SrsState, Tag } from "@/lib/types";

// One question's whole story: the verbatim log makes the grouped wrong
// answers and the diff highlight possible. Everything is derived from the
// question id.
export default function QuestionHistory() {
  const { id } = useParams<{ id: string }>();
  const [agg, setAgg] = useState<QAgg | null>(null);
  const [lesson, setLesson] = useState<Lesson | null>(null);
  const [lessons, setLessons] = useState<Lesson[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [editing, setEditing] = useState(false);
  const [resetting, setResetting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [qr, lr, sr, ar, tr, qtr] = await Promise.all([
      supabase.from("questions").select("*").eq("id", id).maybeSingle(),
      supabase.from("lessons").select("*").order("taught_on", { ascending: false }),
      supabase.from("srs_state").select("*").eq("question_id", id).maybeSingle(),
      supabase.from("attempts").select("*").eq("question_id", id).order("answered_at", { ascending: false }),
      supabase.from("tags").select("*"),
      supabase.from("question_tags").select("*").eq("question_id", id),
    ]);
    const err = qr.error ?? lr.error ?? sr.error ?? ar.error ?? tr.error ?? qtr.error;
    if (err) return setError(err.message);
    const q = qr.data as Question | null;
    if (!q) return setError("No such question.");
    const all = (tr.data ?? []) as Tag[];
    const mine = ((qtr.data ?? []) as QuestionTag[]).map((l) => all.find((t) => t.id === l.tag_id)).filter((t): t is Tag => !!t);
    setTags(all);
    setLessons(lr.data ?? []);
    setLesson((lr.data ?? []).find((l: Lesson) => l.id === q.lesson_id) ?? null);
    setAgg(questionAgg(q, (ar.data ?? []) as Attempt[], sr.data as SrsState | null, mine));
  }, [id]);
  useEffect(() => { load(); }, [load]);

  async function resetToDayOne() {
    if (!confirm("Reset this question to day one? Its schedule restarts from unseen; the attempt history stays.")) return;
    setResetting(true);
    const { error } = await supabase.rpc("reset_srs", { question_ids: [id] });
    setResetting(false);
    if (error) return setError(error.message);
    load();
  }

  if (error) return <p className="error" style={{ padding: 34 }}>{error}</p>;
  if (!agg) return null;

  const q = agg.question;
  const misses = agg.attempts.filter((a) => !a.correct);
  const typedMisses = misses.filter((a) => a.typed && normalize(a.typed)).length;
  const pattern = dominantPattern(agg);
  const log = [...agg.attempts].reverse();
  const expected = q.answers[0] ?? "";
  const grouped = agg.wrong;
  const topShare = grouped[0] ? grouped[0].count / typedMisses : 0;
  const heading = grouped.length === 0
    ? "No wrong answers yet"
    : grouped.length === 1
      ? `The same mistake, ${numWord(grouped[0].count)} time${grouped[0].count === 1 ? "" : "s"}`
      : topShare >= 0.6
        ? `Mostly the same mistake — ${numWord(grouped[0].count)} of ${numWord(typedMisses)}`
        : `${cap(numWord(grouped.length))} different wrong answers`;

  return (
    <div className="page" style={{ maxWidth: 960, margin: "0 auto", width: "100%" }}>
      <div className="row end" style={{ gap: 18 }}>
        <div>
          <div className="card-kicker">
            {lesson ? <Link href={`/lessons/${lesson.id}`}>{lesson.title ? <span lang="ja">{lesson.title}</span> : lesson.taught_on}</Link> : "lesson"} / question
          </div>
          <h3 style={{ margin: "2px 0 6px", fontSize: 30 }} lang="ja">{q.prompt}</h3>
          <div className="tags">
            <span className="tag tag-neutral">{directionLabel(q.direction)}</span>
            {agg.tags.filter((t) => t.kind !== "vocabulary").map((t) => <span key={t.id} className="tag tag-accent" lang="ja">{t.label_ja}</span>)}
            {agg.tags.filter((t) => t.kind === "vocabulary").map((t) => <span key={t.id} className="tag tag-outline">{t.label_en ?? t.label_ja}</span>)}
            {!q.active && <span className="tag tag-neutral">inactive</span>}
          </div>
        </div>
        <span className="spacer" />
        <button className="btn btn-secondary" onClick={() => setEditing(true)}>Edit question</button>
        <button className="btn btn-primary" disabled={resetting || !agg.srs} onClick={resetToDayOne}
                title={agg.srs ? undefined : "Never asked yet — already at day one"}>Reset to day one</button>
      </div>

      <div className="grid-5">
        <StatCard value={fmtPct(agg.firstTry)} label="first try correct" />
        <StatCard value={String(agg.tries)} label="times asked" />
        <StatCard value={agg.avgFirstKey == null ? "—" : (agg.avgFirstKey / 1000).toFixed(1)} unit={agg.avgFirstKey == null ? undefined : "s"} label="to first keystroke" />
        <StatCard value={agg.avgTyping == null ? "—" : (agg.avgTyping / 1000).toFixed(1)} unit={agg.avgTyping == null ? undefined : "s"} label="typing after that" />
        <StatCard value={String(agg.selfCorrected)} label="self-corrected" />
      </div>

      <Blueprint className="pad-18">
        <div className="row base">
          <h6 style={{ margin: 0 }}>{heading}</h6>
          <span className="muted tiny">wrong answers grouped, expected <span lang="ja">{expected}</span></span>
        </div>
        {grouped.length === 0 ? (
          <Empty>{agg.tries === 0 ? "Not asked yet." : misses.length ? "Every miss was a skip — nothing was typed." : "Every answer so far was right."}</Empty>
        ) : (
          <div className="bar-grid" style={{ gridTemplateColumns: "190px 1fr 44px", gap: "9px 14px", fontSize: 13 }}>
            {grouped.map((g) => (
              <Frag key={g.typed}>
                <span lang="ja" style={{ fontSize: 15 }}>{g.typed}</span>
                <span className="bar"><span style={{ width: `${Math.round((g.count / typedMisses) * 100)}%` }} /></span>
                <span className="mono muted n">{g.count}</span>
              </Frag>
            ))}
          </div>
        )}
        {pattern && <p className="prose-13" style={{ marginTop: 4 }}>{patternSentence(pattern)}</p>}
      </Blueprint>

      <Blueprint className="pad-18">
        <h6 style={{ margin: 0 }}>Attempt log</h6>
        {log.length === 0 ? <Empty>No attempts yet.</Empty> : (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>when</th><th>what you typed</th><th>vs expected</th><th>result</th><th>self-corrected</th><th>to 1st key</th><th>total</th><th>hint</th></tr>
              </thead>
              <tbody>
                {log.map((a) => {
                  const typed = a.typed ?? "";
                  const exp = expectedFor(a, q);
                  const skipped = !normalize(typed);
                  const exact = !skipped && normalize(typed) === normalize(exp);
                  return (
                    <tr key={a.id}>
                      <td className="mono">{fmtWhen(a.answered_at)}</td>
                      <td className="ja" lang="ja">{skipped ? <span className="muted">—</span> : typed}</td>
                      <td className="ja">
                        {skipped ? <span className="muted">skipped</span>
                          : a.correct ? <span className="muted">{exact ? "exact" : "accepted"}</span>
                          : <DiffText submitted={typed} expected={exp} />}
                      </td>
                      <td className={a.correct ? "mono" : "muted"}>{a.correct ? "right" : "wrong"}</td>
                      <td className={a.self_corrected ? "mono" : "muted"}>{a.self_corrected ? "yes" : "—"}</td>
                      <td className="mono" style={a.timing_unreliable ? { opacity: .45 } : undefined}>{fmtSec(a.ms_to_first_input)}</td>
                      <td className="mono" style={a.timing_unreliable ? { opacity: .45 } : undefined}>{fmtSec(a.active_ms)}</td>
                      <td className="mono muted">{a.hint_used ? "used" : "—"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        <div className="muted tiny">The highlight marks where your answer diverged from the expected reading. Faded times were flagged as stalled and are left out of the averages.</div>
      </Blueprint>

      {editing && (
        <QuestionEditor
          question={q}
          lessons={lessons}
          tags={tags}
          questionTagIds={agg.tags.map((t) => t.id)}
          defaultLessonId={q.lesson_id}
          maxPosition={() => q.position}
          onClose={(saved) => { setEditing(false); if (saved) load(); }}
        />
      )}
    </div>
  );
}

function Frag({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}
