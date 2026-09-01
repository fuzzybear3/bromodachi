"use client";
import { supabase } from "@/lib/supabase/client";
import type { Lesson, Question } from "@/lib/types";
import Link from "next/link";

// One collapsible section per lesson; newest arrives expanded from the page.
// Active toggles (question-level AND lesson-level) are the ONLY retirement
// mechanism - no delete exists. The two flags are independent: disabling a
// lesson never touches its question rows.
export function LessonSection({ lesson, questions, open, onEdit, onChanged }: {
  lesson: Lesson;
  questions: Question[];
  open: boolean;
  onEdit: (q: Question) => void;
  onChanged: () => void;
}) {
  const active = questions.filter((q) => q.active).length;

  async function toggle(q: Question) {
    await supabase.from("questions").update({ active: !q.active }).eq("id", q.id);
    onChanged();
  }

  async function toggleLesson(e: React.MouseEvent) {
    e.preventDefault(); // a button inside <summary> must not toggle the fold
    await supabase.from("lessons").update({ active: !lesson.active }).eq("id", lesson.id);
    onChanged();
  }

  return (
    <details className="lesson" open={open} style={lesson.active ? undefined : { opacity: 0.5 }}>
      <summary>
        {lesson.taught_on}
        {lesson.title ? <span lang="ja">{lesson.title}</span> : null}
        <span className="count">
          {lesson.active ? `${active}/${questions.length} active` : "lesson disabled"}
        </span>
        <span style={{ flex: 1 }} />
        <button onClick={toggleLesson}>
          {lesson.active ? "disable lesson" : "enable lesson"}
        </button>
      </summary>
      <div className="rows">
        {questions.map((q) => (
          <div className={`qrow${q.active ? "" : " inactive"}`} key={q.id}>
            <span className="type">{q.type}</span>
            <span className="prompt" lang="ja">
              <Link href={`/questions/${q.id}`}>{q.prompt}</Link>
              {q.hint ? <span className="muted"> · {q.hint}</span> : null}
            </span>
            <button onClick={() => onEdit(q)}>edit</button>
            <button onClick={() => toggle(q)}>{q.active ? "deactivate" : "activate"}</button>
          </div>
        ))}
      </div>
    </details>
  );
}
