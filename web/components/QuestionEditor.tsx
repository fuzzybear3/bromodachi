"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { AnswersInput } from "./AnswersInput";
import type { Lesson, Question, QuestionType } from "@/lib/types";

const TYPES: QuestionType[] = ["reading", "en2ja", "grammar", "conj", "cloze"];

// One modal for add and edit. Save is insert or update; position is
// assigned on insert as max+1 within the lesson.
export function QuestionEditor({ question, lessons, defaultLessonId, maxPosition, onClose }: {
  question: Question | null;
  lessons: Lesson[];
  defaultLessonId: string;
  maxPosition: (lessonId: string) => number;
  onClose: (saved: boolean) => void;
}) {
  const [type, setType] = useState<QuestionType>(question?.type ?? "reading");
  const [prompt, setPrompt] = useState(question?.prompt ?? "");
  const [answers, setAnswers] = useState<string[]>(question?.answers ?? []);
  const [hint, setHint] = useState(question?.hint ?? "");
  const [ja, setJa] = useState(question?.ja ?? true);
  const [active, setActive] = useState(question?.active ?? true);
  const [lessonId, setLessonId] = useState(question?.lesson_id ?? defaultLessonId);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    setError(null);
    const fields = {
      type, prompt: prompt.trim(), answers, hint: hint.trim() || null,
      ja, active, lesson_id: lessonId,
    };
    const { error } = question
      ? await supabase.from("questions")
          .update({ ...fields, updated_at: new Date().toISOString() })
          .eq("id", question.id)
      : await supabase.from("questions")
          .insert({ ...fields, position: maxPosition(lessonId) + 1 });
    if (error) {
      setError(error.message);
      setBusy(false);
    } else {
      onClose(true);
    }
  }

  return (
    <div className="overlay" onClick={() => onClose(false)}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>{question ? "Edit question" : "New question"}</h2>
        <div className="row">
          <div>
            <label>Lesson</label>
            <select value={lessonId} onChange={(e) => setLessonId(e.target.value)}>
              {lessons.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.taught_on}{l.title ? ` · ${l.title}` : ""}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label>Type</label>
            <select value={type} onChange={(e) => setType(e.target.value as QuestionType)}>
              {TYPES.map((t) => <option key={t}>{t}</option>)}
            </select>
          </div>
        </div>
        <label>Prompt</label>
        <textarea lang="ja" rows={2} value={prompt} onChange={(e) => setPrompt(e.target.value)} />
        <label>Accepted answers - every spelling variant (grading is exact-match)</label>
        <AnswersInput value={answers} onChange={setAnswers} />
        <label>Hint - in N5 Japanese; shown on F1 and as the meaning line. Never the answer itself.</label>
        <input type="text" lang="ja" value={hint} onChange={(e) => setHint(e.target.value)} />
        <div className="row" style={{ marginTop: 10 }}>
          <label style={{ display: "flex", gap: 6, alignItems: "center" }}>
            <input type="checkbox" checked={ja} onChange={(e) => setJa(e.target.checked)}
                   style={{ width: "auto" }} />
            Japanese IME on
          </label>
          <label style={{ display: "flex", gap: 6, alignItems: "center" }}>
            <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)}
                   style={{ width: "auto" }} />
            Active (asked by the buddy)
          </label>
        </div>
        {error && <p className="error">{error}</p>}
        <div className="actions">
          <button onClick={() => onClose(false)}>Cancel</button>
          <button className="primary" disabled={busy || !prompt.trim() || answers.length === 0}
                  onClick={save}>
            Save
          </button>
        </div>
      </div>
    </div>
  );
}
