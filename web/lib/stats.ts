// Pure aggregations for the dashboard. Rows number in the hundreds, so
// everything is computed client-side; complexity scaling of times happens
// HERE, at read time - raw active_ms is never rewritten.
import type { Attempt, Lesson, Question, SrsState } from "./types";

const MASTERED_MIN = 10080; // interval >= 7 days counts as mastered

export function dueCount(
  questions: Question[],
  srs: Map<string, SrsState>,
  now: Date,
): number {
  return questions.filter((q) => {
    if (!q.active) return false;
    const s = srs.get(q.id);
    return !s || new Date(s.due_at) <= now;
  }).length;
}

export interface LessonMastery {
  lesson: Lesson;
  mastered: number;
  total: number;
}

export function masteryByLesson(
  lessons: Lesson[],
  questions: Question[],
  srs: Map<string, SrsState>,
): LessonMastery[] {
  return lessons.map((lesson) => {
    const qs = questions.filter((q) => q.lesson_id === lesson.id && q.active);
    const mastered = qs.filter((q) => {
      const s = srs.get(q.id);
      return !!s && s.interval_min >= MASTERED_MIN && s.last_correct === true;
    }).length;
    return { lesson, mastered, total: qs.length };
  });
}

/** Consecutive days with at least one attempt, counting back from today
 *  (or yesterday, if today has none yet). Local dates. */
export function dayStreak(attempts: Attempt[], today: Date): number {
  const days = new Set(attempts.map((a) => toLocalDay(new Date(a.answered_at))));
  let cursor = toLocalDay(today);
  if (!days.has(cursor)) cursor = addDays(cursor, -1);
  let streak = 0;
  while (days.has(cursor)) {
    streak++;
    cursor = addDays(cursor, -1);
  }
  return streak;
}

export function accuracy(attempts: Attempt[]): number | null {
  if (attempts.length === 0) return null;
  return attempts.filter((a) => a.correct).length / attempts.length;
}

export interface DayPoint {
  day: string;
  correct: number;
  total: number;
}

export function dailyAccuracy(attempts: Attempt[], days: number, today: Date): DayPoint[] {
  const byDay = new Map<string, DayPoint>();
  for (let i = days - 1; i >= 0; i--) {
    const d = addDays(toLocalDay(today), -i);
    byDay.set(d, { day: d, correct: 0, total: 0 });
  }
  for (const a of attempts) {
    const d = toLocalDay(new Date(a.answered_at));
    const p = byDay.get(d);
    if (p) {
      p.total++;
      if (a.correct) p.correct++;
    }
  }
  return [...byDay.values()];
}

/** Complexity-scaled solve speed: active ms per character of the canonical
 *  answer. Comparable across 「りょう」 and full sentences. */
export function msPerChar(a: Attempt, q: Question): number | null {
  if (a.active_ms == null || q.answers.length === 0) return null;
  const len = [...q.answers[0]].length;
  return len > 0 ? a.active_ms / len : null;
}

/** This attempt against the same question's own median active time - the
 *  honest "was that slow for me on this one". >1 = slower than usual. */
export function vsOwnMedian(a: Attempt, history: Attempt[]): number | null {
  const times = history
    .filter((h) => h.question_id === a.question_id && h.active_ms != null && h.id !== a.id)
    .map((h) => h.active_ms as number)
    .sort((x, y) => x - y);
  if (times.length === 0 || a.active_ms == null) return null;
  const median = times[Math.floor(times.length / 2)];
  return median > 0 ? a.active_ms / median : null;
}

export function hintRate(attempts: Attempt[]): number | null {
  if (attempts.length === 0) return null;
  return attempts.filter((a) => a.hint_used).length / attempts.length;
}

function toLocalDay(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function addDays(day: string, n: number): string {
  const [y, m, d] = day.split("-").map(Number);
  const date = new Date(y, m - 1, d + n);
  return toLocalDay(date);
}

/** One row per ISO week (Monday start), newest first, derived purely from
 *  the attempts log. "New words" = first attempt within the fetched window,
 *  which currently spans the whole history (90-day fetch, project is young);
 *  revisit if the window ever truncates real history. */
export interface WeekRow {
  weekStart: string;
  answers: number;
  correct: number;
  activeMs: number;
  distinct: number;
  newSeen: number;
  hintUsed: number;
}

export function weeklyRollup(attempts: Attempt[], maxWeeks: number): WeekRow[] {
  const firstSeen = new Map<string, string>(); // question -> week of first attempt
  const weeks = new Map<string, WeekRow>();
  const sorted = [...attempts].sort(
    (a, b) => a.answered_at.localeCompare(b.answered_at),
  );
  for (const a of sorted) {
    const w = mondayOf(new Date(a.answered_at));
    let row = weeks.get(w);
    if (!row) {
      row = { weekStart: w, answers: 0, correct: 0, activeMs: 0, distinct: 0, newSeen: 0, hintUsed: 0 };
      weeks.set(w, row);
    }
    row.answers++;
    if (a.correct) row.correct++;
    if (a.hint_used) row.hintUsed++;
    row.activeMs += a.active_ms ?? 0;
    if (!firstSeen.has(a.question_id)) {
      firstSeen.set(a.question_id, w);
      row.newSeen++;
    }
  }
  for (const row of weeks.values()) {
    row.distinct = new Set(
      sorted
        .filter((a) => mondayOf(new Date(a.answered_at)) === row.weekStart)
        .map((a) => a.question_id),
    ).size;
  }
  return [...weeks.values()].sort((a, b) => b.weekStart.localeCompare(a.weekStart)).slice(0, maxWeeks);
}

/** Per-question rollup for the lesson page, trouble sorted first:
 *  most lapses, then lowest accuracy, then most attempts. */
export interface QuestionStats {
  question: Question;
  tries: number;
  correct: number;
  hintUsed: number;
  avgActiveMs: number | null;
  srs: SrsState | null;
}

export function perQuestionStats(
  questions: Question[],
  attempts: Attempt[],
  srs: Map<string, SrsState>,
): QuestionStats[] {
  const rows = questions.map((question) => {
    const mine = attempts.filter((a) => a.question_id === question.id);
    const timed = mine.filter((a) => a.active_ms != null);
    return {
      question,
      tries: mine.length,
      correct: mine.filter((a) => a.correct).length,
      hintUsed: mine.filter((a) => a.hint_used).length,
      avgActiveMs: timed.length
        ? timed.reduce((s, a) => s + (a.active_ms as number), 0) / timed.length
        : null,
      srs: srs.get(question.id) ?? null,
    };
  });
  return rows.sort((a, b) => {
    const lapses = (b.srs?.lapses ?? 0) - (a.srs?.lapses ?? 0);
    if (lapses !== 0) return lapses;
    const acc = (a.tries ? a.correct / a.tries : 1) - (b.tries ? b.correct / b.tries : 1);
    if (acc !== 0) return acc;
    return b.tries - a.tries;
  });
}

function mondayOf(d: Date): string {
  const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const dow = (day.getDay() + 6) % 7; // Monday = 0
  day.setDate(day.getDate() - dow);
  return `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, "0")}-${String(day.getDate()).padStart(2, "0")}`;
}
