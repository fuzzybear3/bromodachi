"use client";
import { supabase } from "@/lib/supabase/client";
import type { Lesson, Question, Tag } from "@/lib/types";
import Link from "next/link";

// One collapsible section per lesson; newest arrives expanded from the page.
// Active toggles (question-level AND lesson-level) are the ONLY retirement
// mechanism - no delete exists. The two flags are independent: disabling a
// lesson never touches its question rows.
export function LessonSection({ lesson, questions, tagsByQuestion, open, onEdit, onChanged }: {
  lesson: Lesson;
  questions: Question[];
  tagsByQuestion: Map<string, Tag[]>;
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
    <details className="lesson" open={open} style={lesson.active ? undefined : { opacity: 0.55 }}>
      <summary>
        <span className="mono">{lesson.taught_on}</span>
        {lesson.title ? <span lang="ja">{lesson.title}</span> : null}
        <span className="count muted">
          {lesson.active ? `${active}/${questions.length} active` : "lesson disabled"}
        </span>
        <span className="spacer" />
        <Link className="btn btn-ghost" href={`/lessons/${lesson.id}`} onClick={(e) => e.stopPropagation()}>Lesson review</Link>
        <button className="btn btn-secondary" onClick={toggleLesson}>
          {lesson.active ? "Disable lesson" : "Enable lesson"}
        </button>
      </summary>
      <div className="rows">
        {questions.map((q) => (
          <div className={`qrow${q.active ? "" : " inactive"}`} key={q.id}>
            <span className="tag tag-neutral">{q.type}</span>
            <span className="prompt" lang="ja">
              <Link href={`/questions/${q.id}`}>{q.prompt}</Link>
              {q.hint ? <span className="muted"> · {q.hint}</span> : null}
            </span>
            <span className="tags">
              {(tagsByQuestion.get(q.id) ?? []).map((t) => <span key={t.id} className="tag tag-accent" lang="ja">{t.label_ja}</span>)}
            </span>
            <button className="btn btn-ghost" onClick={() => onEdit(q)}>edit</button>
            <button className="btn btn-ghost" onClick={() => toggle(q)}>{q.active ? "deactivate" : "activate"}</button>
          </div>
        ))}
      </div>
    </details>
  );
}
