"use client";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { StatCards } from "@/components/StatCards";
import { MasteryBars } from "@/components/MasteryBars";
import { TrendChart } from "@/components/TrendChart";
import { RecentMisses } from "@/components/RecentMisses";
import * as stats from "@/lib/stats";
import type { Attempt, Lesson, Question, SrsState } from "@/lib/types";

interface Data {
  lessons: Lesson[];
  questions: Question[];
  srs: Map<string, SrsState>;
  attempts: Attempt[]; // last 90 days, ascending
  totalAttempts: number;
}

export default function Dashboard() {
  const [data, setData] = useState<Data | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const since = new Date(Date.now() - 90 * 86400_000).toISOString();
    Promise.all([
      supabase.from("lessons").select("*").order("taught_on", { ascending: false }),
      supabase.from("questions").select("*"),
      supabase.from("srs_state").select("*"),
      supabase.from("attempts").select("*").gte("answered_at", since).order("answered_at"),
      supabase.from("attempts").select("id", { count: "exact", head: true }),
    ]).then(([lessons, questions, srs, attempts, total]) => {
      const err = lessons.error ?? questions.error ?? srs.error ?? attempts.error ?? total.error;
      if (err) return setError(err.message);
      setData({
        lessons: lessons.data ?? [],
        questions: (questions.data ?? []) as Question[],
        srs: new Map(((srs.data ?? []) as SrsState[]).map((s) => [s.question_id, s])),
        attempts: (attempts.data ?? []) as Attempt[],
        totalAttempts: total.count ?? 0,
      });
    });
  }, []);

  if (error) return <p className="error">{error}</p>;
  if (!data) return null;

  const now = new Date();
  const last30 = data.attempts.filter(
    (a) => new Date(a.answered_at) > new Date(Date.now() - 30 * 86400_000),
  );
  const acc = stats.accuracy(last30);
  const hint = stats.hintRate(last30);
  const misses = [...data.attempts].reverse().filter((a) => !a.correct).slice(0, 10);
  const qById = new Map(data.questions.map((q) => [q.id, q]));

  return (
    <>
      <StatCards
        cards={[
          { big: String(stats.dueCount(data.questions, data.srs, now)), label: "due now" },
          { big: String(data.totalAttempts), label: "total answers" },
          { big: String(stats.dayStreak(data.attempts, now)), label: "day streak" },
          { big: acc == null ? "—" : `${Math.round(acc * 100)}%`, label: "accuracy (30d)" },
          { big: hint == null ? "—" : `${Math.round(hint * 100)}%`, label: "hint used (30d)" },
        ]}
      />
      <MasteryBars rows={stats.masteryByLesson(data.lessons, data.questions, data.srs)} />
      <TrendChart points={stats.dailyAccuracy(data.attempts, 30, now)} />
      <RecentMisses misses={misses} questions={qById} />
    </>
  );
}
