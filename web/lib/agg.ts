// Read-time aggregates for the training console. Rows number in the
// hundreds to low thousands, so every screen computes from raw attempts in
// the browser; nothing here is stored. Time metrics use the ACTIVE clock
// and skip attempts the view flagged as timing_unreliable.
//
// "first try" = correct / tries. The buddy records exactly one graded
// answer per pop (the drill re-type is never an attempt), so there is no
// separate "eventually" figure — that column was dropped from the design.
import type { Attempt, Direction, Lesson, Question, QuestionType, SrsState, Tag } from "./types";
import { normalize, soleHunk } from "./diff";
import { localDay, numWord, cap } from "./format";

export const MASTERED_MIN = 10080; // interval ≥ 7 days
export const NOT_STICKING_ACC = 0.65;
export const SESSION_GAP_MS = 30 * 60_000;

export type Mastery = "mastered" | "learning" | "notSticking";

export interface WrongGroup {
  typed: string; // as first seen, raw
  count: number;
}

export interface QAgg {
  question: Question;
  tags: Tag[];
  srs: SrsState | null;
  attempts: Attempt[]; // ascending by answered_at
  tries: number;
  correct: number;
  firstTry: number | null;
  hintRate: number | null;
  avgFirstKey: number | null;
  avgTotal: number | null;
  avgTyping: number | null;
  selfCorrected: number;
  lapses: number;
  last6: boolean[]; // oldest first
  wrong: WrongGroup[]; // most common first
  mostCommonWrong: string | null;
  mastery: Mastery;
}

export function mean(xs: number[]): number | null {
  return xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : null;
}

export function ratio(num: number, den: number): number | null {
  return den > 0 ? num / den : null;
}

const timed = (as: Attempt[]) => as.filter((a) => !a.timing_unreliable);

export function expectedFor(a: Attempt, q: Question): string {
  return a.expected_text ?? q.answers[0] ?? "";
}

export function wrongGroups(attempts: Attempt[]): WrongGroup[] {
  const groups = new Map<string, WrongGroup>();
  for (const a of attempts) {
    if (a.correct || !a.typed) continue;
    const key = normalize(a.typed);
    if (!key) continue;
    const g = groups.get(key);
    if (g) g.count++;
    else groups.set(key, { typed: a.typed, count: 1 });
  }
  return [...groups.values()].sort((x, y) => y.count - x.count);
}

export function classify(tries: number, firstTry: number | null, srs: SrsState | null, lastCorrect: boolean | null): Mastery {
  if (srs && srs.interval_min >= MASTERED_MIN && lastCorrect === true) return "mastered";
  if ((srs?.lapses ?? 0) >= 2) return "notSticking";
  if (tries > 0 && firstTry != null && firstTry < NOT_STICKING_ACC) return "notSticking";
  return "learning";
}

export function questionAgg(question: Question, attemptsAny: Attempt[], srs: SrsState | null, tags: Tag[]): QAgg {
  const attempts = [...attemptsAny].sort((a, b) => a.answered_at.localeCompare(b.answered_at));
  const tries = attempts.length;
  const correct = attempts.filter((a) => a.correct).length;
  const firstTry = ratio(correct, tries);
  const ok = timed(attempts);
  const firstKeys = ok.filter((a) => a.ms_to_first_input != null).map((a) => a.ms_to_first_input as number);
  const totals = ok.filter((a) => a.active_ms != null).map((a) => a.active_ms as number);
  const typing = ok
    .filter((a) => a.ms_to_first_input != null && a.active_ms != null)
    .map((a) => Math.max(0, (a.active_ms as number) - (a.ms_to_first_input as number)));
  const wrong = wrongGroups(attempts);
  const last = attempts[attempts.length - 1];
  return {
    question, tags, srs, attempts, tries, correct, firstTry,
    hintRate: ratio(attempts.filter((a) => a.hint_used).length, tries),
    avgFirstKey: mean(firstKeys),
    avgTotal: mean(totals),
    avgTyping: mean(typing),
    selfCorrected: attempts.filter((a) => a.self_corrected).length,
    lapses: srs?.lapses ?? 0,
    last6: attempts.slice(-6).map((a) => a.correct),
    wrong,
    mostCommonWrong: wrong[0]?.typed ?? null,
    mastery: classify(tries, firstTry, srs, last ? last.correct : null),
  };
}

export function groupBy<T>(xs: T[], key: (x: T) => string): Map<string, T[]> {
  const m = new Map<string, T[]>();
  for (const x of xs) {
    const k = key(x);
    const arr = m.get(k);
    if (arr) arr.push(x);
    else m.set(k, [x]);
  }
  return m;
}

export function aggAll(
  questions: Question[],
  attempts: Attempt[],
  srs: Map<string, SrsState>,
  tagsByQuestion: Map<string, Tag[]>,
): QAgg[] {
  const byQ = groupBy(attempts, (a) => a.question_id);
  return questions.map((q) =>
    questionAgg(q, byQ.get(q.id) ?? [], srs.get(q.id) ?? null, tagsByQuestion.get(q.id) ?? []),
  );
}

/** Trouble first: lowest first-try accuracy, then most lapses, then most
 *  tries. Never-asked questions sort last. */
export function worstFirst(aggs: QAgg[]): QAgg[] {
  return [...aggs].sort((a, b) => {
    const fa = a.firstTry ?? 2, fb = b.firstTry ?? 2;
    if (fa !== fb) return fa - fb;
    if (a.lapses !== b.lapses) return b.lapses - a.lapses;
    return b.tries - a.tries;
  });
}

export function tagsByQuestion(links: { question_id: string; tag_id: string }[], tags: Tag[]): Map<string, Tag[]> {
  const tagById = new Map(tags.map((t) => [t.id, t]));
  const m = new Map<string, Tag[]>();
  for (const l of links) {
    const t = tagById.get(l.tag_id);
    if (!t) continue;
    const arr = m.get(l.question_id);
    if (arr) arr.push(t);
    else m.set(l.question_id, [t]);
  }
  for (const arr of m.values()) arr.sort((a, b) => a.kind.localeCompare(b.kind) || a.label_ja.localeCompare(b.label_ja));
  return m;
}

// ── lesson-level ─────────────────────────────────────────────────────────

export interface LessonSummary {
  answers: number;
  firstTry: number | null;
  avgFirstKey: number | null;
  hintRate: number | null;
  mastered: number;
  learning: number;
  notSticking: number;
  activeMs: number;
  firstDay: string | null;
  lastDay: string | null;
}

export function lessonSummary(aggs: QAgg[]): LessonSummary {
  const attempts = aggs.flatMap((a) => a.attempts);
  const days = attempts.map((a) => localDay(new Date(a.answered_at))).sort();
  const firstKeys = timed(attempts).filter((a) => a.ms_to_first_input != null).map((a) => a.ms_to_first_input as number);
  return {
    answers: attempts.length,
    firstTry: ratio(attempts.filter((a) => a.correct).length, attempts.length),
    avgFirstKey: mean(firstKeys),
    hintRate: ratio(attempts.filter((a) => a.hint_used).length, attempts.length),
    mastered: aggs.filter((a) => a.mastery === "mastered").length,
    learning: aggs.filter((a) => a.mastery === "learning").length,
    notSticking: aggs.filter((a) => a.mastery === "notSticking").length,
    activeMs: attempts.reduce((s, a) => s + (a.active_ms ?? 0), 0),
    firstDay: days[0] ?? null,
    lastDay: days[days.length - 1] ?? null,
  };
}

export interface KeyedRate {
  key: string;
  n: number; // attempts
  questions: number;
  firstTry: number | null;
}

function rateBy(aggs: QAgg[], key: (a: QAgg) => string): KeyedRate[] {
  const m = groupBy(aggs, key);
  return [...m.entries()]
    .map(([k, group]) => {
      const tries = group.reduce((s, a) => s + a.tries, 0);
      const correct = group.reduce((s, a) => s + a.correct, 0);
      return { key: k, n: tries, questions: group.length, firstTry: ratio(correct, tries) };
    })
    .filter((r) => r.n > 0)
    .sort((a, b) => (a.firstTry ?? 2) - (b.firstTry ?? 2));
}

export const byDirection = (aggs: QAgg[]) => rateBy(aggs, (a) => a.question.direction) as (KeyedRate & { key: Direction })[];
export const byType = (aggs: QAgg[]) => rateBy(aggs, (a) => a.question.type) as (KeyedRate & { key: QuestionType })[];

// ── the interpretive sentences ───────────────────────────────────────────
// Only when the data is unambiguous; otherwise null and the UI omits the
// paragraph rather than guessing.

export interface Pattern {
  del: string;
  ins: string;
  count: number;
  misses: number;
}

/** One divergence span accounting for >80% of a question's misses. */
export function dominantPattern(agg: QAgg): Pattern | null {
  const misses = agg.attempts.filter((a) => !a.correct && a.typed && normalize(a.typed));
  if (misses.length < 2) return null;
  const counts = new Map<string, Pattern>();
  for (const a of misses) {
    const h = soleHunk(a.typed as string, expectedFor(a, agg.question));
    if (!h) continue;
    const key = `${h.del}→${h.ins}`;
    const p = counts.get(key);
    if (p) p.count++;
    else counts.set(key, { del: h.del, ins: h.ins, count: 1, misses: misses.length });
  }
  const top = [...counts.values()].sort((a, b) => b.count - a.count)[0];
  return top && top.count / misses.length > 0.8 ? top : null;
}

export function patternSentence(p: Pattern): string {
  const n = `${cap(numWord(p.count))} of ${numWord(p.misses)} misses`;
  if (p.del && p.ins) return `${n} replace 「${p.del}」 with 「${p.ins}」 — the rest of the answer is right every time.`;
  if (p.del) return `${n} drop 「${p.del}」 — the rest of the answer is right every time.`;
  return `${n} add 「${p.ins}」 — the rest of the answer is right every time.`;
}

// ── tags ─────────────────────────────────────────────────────────────────

export interface TrendBar {
  h: number; // 0–100, accuracy of the period
  on: boolean; // beat the previous period
  n: number;
}

export interface TagAgg {
  tag: Tag;
  aggs: QAgg[];
  questions: number;
  lessons: number;
  tries: number;
  firstTry: number | null;
  hintRate: number | null;
  avgFirstKey: number | null;
  selfCorrects: number;
  trend: TrendBar[];
}

export function tagAgg(tag: Tag, aggs: QAgg[], now: Date): TagAgg {
  const attempts = aggs.flatMap((a) => a.attempts);
  const tries = attempts.length;
  const firstKeys = timed(attempts).filter((a) => a.ms_to_first_input != null).map((a) => a.ms_to_first_input as number);
  return {
    tag, aggs,
    questions: aggs.length,
    lessons: new Set(aggs.map((a) => a.question.lesson_id)).size,
    tries,
    firstTry: ratio(attempts.filter((a) => a.correct).length, tries),
    hintRate: ratio(attempts.filter((a) => a.hint_used).length, tries),
    avgFirstKey: mean(firstKeys),
    selfCorrects: attempts.filter((a) => a.self_corrected).length,
    trend: weeklyTrend(attempts, 6, now),
  };
}

/** Accuracy per ISO week for the last `n` weeks, oldest first; a bar is
 *  "on" when the week beat the previous week that had data. */
export function weeklyTrend(attempts: Attempt[], n: number, now: Date): TrendBar[] {
  const weeks = lastWeeks(n, now);
  const byWeek = groupBy(attempts, (a) => mondayOf(new Date(a.answered_at)));
  let prev: number | null = null;
  return weeks.map((w) => {
    const as = byWeek.get(w) ?? [];
    const acc = ratio(as.filter((a) => a.correct).length, as.length);
    const bar = { h: acc == null ? 0 : Math.max(8, Math.round(acc * 100)), on: acc != null && prev != null && acc > prev, n: as.length };
    if (acc != null) prev = acc;
    return bar;
  });
}

// ── time series & sessions ───────────────────────────────────────────────

export function mondayOf(d: Date): string {
  const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const dow = (day.getDay() + 6) % 7;
  day.setDate(day.getDate() - dow);
  return localDay(day);
}

export function lastWeeks(n: number, now: Date): string[] {
  const out: string[] = [];
  const [y, m, d] = mondayOf(now).split("-").map(Number);
  for (let i = n - 1; i >= 0; i--) out.push(localDay(new Date(y, m - 1, d - 7 * i)));
  return out;
}

export interface WeekCol {
  weekStart: string;
  answers: number;
  correct: number;
}

export function weekColumns(attempts: Attempt[], n: number, now: Date): WeekCol[] {
  const byWeek = groupBy(attempts, (a) => mondayOf(new Date(a.answered_at)));
  return lastWeeks(n, now).map((w) => {
    const as = byWeek.get(w) ?? [];
    return { weekStart: w, answers: as.length, correct: as.filter((a) => a.correct).length };
  });
}

export interface SessionRow {
  startedAt: string;
  lesson: Lesson | null;
  answers: number;
  correct: number;
  hintUsed: number;
  activeMs: number;
  avgMs: number | null;
}

/** Cluster attempts into sittings: a gap over SESSION_GAP_MS starts a new
 *  one. The lesson shown is the one most of the session's answers came from. */
export function sessions(attempts: Attempt[], qById: Map<string, Question>, lessonById: Map<string, Lesson>): SessionRow[] {
  const sorted = [...attempts].sort((a, b) => a.answered_at.localeCompare(b.answered_at));
  const groups: Attempt[][] = [];
  let last: number | null = null;
  for (const a of sorted) {
    const t = new Date(a.answered_at).getTime();
    if (last == null || t - last > SESSION_GAP_MS) groups.push([]);
    groups[groups.length - 1].push(a);
    last = t;
  }
  return groups.map((g) => {
    const lessonCounts = new Map<string, number>();
    for (const a of g) {
      const lid = qById.get(a.question_id)?.lesson_id;
      if (lid) lessonCounts.set(lid, (lessonCounts.get(lid) ?? 0) + 1);
    }
    const top = [...lessonCounts.entries()].sort((x, y) => y[1] - x[1])[0]?.[0];
    const times = timed(g).filter((a) => a.active_ms != null).map((a) => a.active_ms as number);
    return {
      startedAt: g[0].answered_at,
      lesson: top ? lessonById.get(top) ?? null : null,
      answers: g.length,
      correct: g.filter((a) => a.correct).length,
      hintUsed: g.filter((a) => a.hint_used).length,
      activeMs: g.reduce((s, a) => s + (a.active_ms ?? 0), 0),
      avgMs: mean(times),
    };
  }).reverse();
}

export function dueCount(questions: Question[], srs: Map<string, SrsState>, now: Date): number {
  return questions.filter((q) => {
    if (!q.active) return false;
    const s = srs.get(q.id);
    return !s || new Date(s.due_at) <= now;
  }).length;
}

/** Consecutive days with at least one attempt, counting back from today
 *  (or yesterday, if today has none yet). */
export function dayStreak(attempts: Attempt[], today: Date): number {
  const days = new Set(attempts.map((a) => localDay(new Date(a.answered_at))));
  let cursor = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  if (!days.has(localDay(cursor))) cursor.setDate(cursor.getDate() - 1);
  let streak = 0;
  while (days.has(localDay(cursor))) {
    streak++;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}

export function accuracy(attempts: Attempt[]): number | null {
  return ratio(attempts.filter((a) => a.correct).length, attempts.length);
}

export function hintRate(attempts: Attempt[]): number | null {
  return ratio(attempts.filter((a) => a.hint_used).length, attempts.length);
}

export function since(attempts: Attempt[], days: number, now: Date): Attempt[] {
  const cutoff = now.getTime() - days * 86400_000;
  return attempts.filter((a) => new Date(a.answered_at).getTime() > cutoff);
}
