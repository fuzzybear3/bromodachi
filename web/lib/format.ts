import type { Direction } from "./types";

export function fmtDur(ms: number): string {
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
  if (ms < 3_600_000) return `${(ms / 60_000).toFixed(1)} min`;
  return `${(ms / 3_600_000).toFixed(1)} h`;
}

export function fmtMin(min: number): string {
  if (min < 60) return `${Math.round(min)} min`;
  if (min < 1440) return `${(min / 60).toFixed(1)} h`;
  return `${(min / 1440).toFixed(1)} days`;
}

/** Seconds to one decimal, "—" when unmeasured. */
export function fmtSec(ms: number | null | undefined): string {
  return ms == null ? "—" : `${(ms / 1000).toFixed(1)}s`;
}

/** Whole-number percentage, "—" when there is no denominator. */
export function fmtPct(r: number | null | undefined): string {
  return r == null ? "—" : `${Math.round(r * 100)}%`;
}

/** 2026-08-28 → 08-28 */
export function fmtMD(day: string): string {
  return day.slice(5, 10);
}

/** ISO timestamp → "09-02 21:11" in local time. */
export function fmtWhen(iso: string): string {
  const d = new Date(iso);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

export function localDay(d: Date): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function daysAgo(day: string, now: Date): string {
  const [y, m, d] = day.split("-").map(Number);
  const then = new Date(y, m - 1, d);
  const n = Math.round((now.getTime() - then.getTime()) / 86400_000);
  if (n <= 0) return "today";
  if (n === 1) return "yesterday";
  return `${n} days ago`;
}

export const DIRECTIONS: Direction[] = ["kanji_reading", "reading_kanji", "ja_en", "en_ja", "cloze", "ja_ja"];

export function directionLabel(d: Direction): string {
  switch (d) {
    case "kanji_reading": return "kanji → reading";
    case "reading_kanji": return "reading → kanji";
    case "ja_en": return "ja → en";
    case "en_ja": return "en → ja";
    case "cloze": return "cloze";
    case "ja_ja": return "ja → ja";
  }
}

const WORDS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
  "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"];

/** "nine", "twenty", "34" — words up to twenty, digits beyond. */
export function numWord(n: number): string {
  return n >= 0 && n <= 20 ? WORDS[n] : String(n);
}

export function cap(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
