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
