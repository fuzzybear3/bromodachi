"use client";
import { supabase } from "@/lib/supabase/client";
import type { Lesson, Question } from "@/lib/types";
import Link from "next/link";

// One collapsible section per lesson; newest arrives expanded from the page.
// The active toggle is the ONLY retirement mechanism - no delete exists.
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

  return (
    <details className="lesson" open={open}>
      <summary>
        {lesson.taught_on}
        {lesson.title ? <span lang="ja">{lesson.title}</span> : null}
        <span className="count">{active}/{questions.length} active</span>
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
