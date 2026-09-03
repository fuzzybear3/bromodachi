"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { AnswersInput } from "./AnswersInput";
import { TagPicker } from "./TagPicker";
import { Check } from "./ui";
import { DIRECTIONS, directionLabel } from "@/lib/format";
import type { Direction, Lesson, Question, QuestionType, Tag } from "@/lib/types";

const TYPES: QuestionType[] = ["reading", "en2ja", "grammar", "conj", "cloze"];

// The direction a type implies, offered until the teacher picks one herself.
function directionFor(t: QuestionType): Direction {
  switch (t) {
    case "reading": return "kanji_reading";
    case "en2ja": return "en_ja";
    case "cloze": return "cloze";
    default: return "ja_ja";
  }
}

// One modal for add and edit. Save is insert or update; position is
// assigned on insert as max+1 within the lesson. Tag links are diffed
// against what the question had when the editor opened.
export function QuestionEditor({ question, lessons, tags, questionTagIds, defaultLessonId, maxPosition, onClose }: {
  question: Question | null;
  lessons: Lesson[];
  tags: Tag[];
  questionTagIds: string[];
  defaultLessonId: string;
  maxPosition: (lessonId: string) => number;
  onClose: (saved: boolean) => void;
}) {
  const [type, setType] = useState<QuestionType>(question?.type ?? "reading");
  const [direction, setDirection] = useState<Direction>(question?.direction ?? "kanji_reading");
  const [dirTouched, setDirTouched] = useState(!!question);
  const [prompt, setPrompt] = useState(question?.prompt ?? "");
  const [answers, setAnswers] = useState<string[]>(question?.answers ?? []);
  const [hint, setHint] = useState(question?.hint ?? "");
  const [ja, setJa] = useState(question?.ja ?? true);
  const [active, setActive] = useState(question?.active ?? true);
  const [lessonId, setLessonId] = useState(question?.lesson_id ?? defaultLessonId);
  const [allTags, setAllTags] = useState<Tag[]>(tags);
  const [picked, setPicked] = useState<Set<string>>(new Set(questionTagIds));
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  function pickType(t: QuestionType) {
    setType(t);
    if (!dirTouched) setDirection(directionFor(t));
  }

  async function save() {
    setBusy(true);
    setError(null);
    const fields = {
      type, direction, prompt: prompt.trim(), answers, hint: hint.trim() || null,
      ja, active, lesson_id: lessonId,
    };
    let id = question?.id;
    if (question) {
      const { error } = await supabase.from("questions")
        .update({ ...fields, updated_at: new Date().toISOString() })
        .eq("id", question.id);
      if (error) return fail(error.message);
    } else {
      const { data, error } = await supabase.from("questions")
        .insert({ ...fields, position: maxPosition(lessonId) + 1 })
        .select("id").single();
      if (error) return fail(error.message);
      id = data.id as string;
    }
    const before = new Set(questionTagIds);
    const add = [...picked].filter((t) => !before.has(t));
    const remove = [...before].filter((t) => !picked.has(t));
    if (add.length) {
      const { error } = await supabase.from("question_tags").insert(add.map((tag_id) => ({ question_id: id, tag_id })));
      if (error) return fail(error.message);
    }
    if (remove.length) {
      const { error } = await supabase.from("question_tags").delete().eq("question_id", id).in("tag_id", remove);
      if (error) return fail(error.message);
    }
    onClose(true);
  }

  function fail(msg: string) {
    setError(msg);
    setBusy(false);
  }

  return (
    <div className="dialog-backdrop" onClick={() => onClose(false)}>
      <div className="dialog" onClick={(e) => e.stopPropagation()}>
        <div className="dialog-title">{question ? "Edit question" : "New question"}</div>
        <div className="form-row">
          <div className="field">
            <label>Lesson</label>
            <select className="input" value={lessonId} onChange={(e) => setLessonId(e.target.value)}>
              {lessons.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.taught_on}{l.title ? ` · ${l.title}` : ""}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label>Type</label>
            <select className="input" value={type} onChange={(e) => pickType(e.target.value as QuestionType)}>
              {TYPES.map((t) => <option key={t}>{t}</option>)}
            </select>
          </div>
          <div className="field">
            <label>Direction</label>
            <select className="input" value={direction}
                    onChange={(e) => { setDirection(e.target.value as Direction); setDirTouched(true); }}>
              {DIRECTIONS.map((d) => <option key={d} value={d}>{directionLabel(d)}</option>)}
            </select>
          </div>
        </div>
        <div className="field">
          <label>Prompt</label>
          <textarea className="input" lang="ja" rows={2} style={{ minHeight: 60 }} value={prompt} onChange={(e) => setPrompt(e.target.value)} />
        </div>
        <div className="field">
          <label>Accepted answers — every spelling variant (grading is exact-match)</label>
          <AnswersInput value={answers} onChange={setAnswers} />
        </div>
        <div className="field">
          <label>Hint — in N5 Japanese; shown on F1 and as the meaning line. Never the answer itself.</label>
          <input className="input" type="text" lang="ja" value={hint} onChange={(e) => setHint(e.target.value)} />
        </div>
        <div className="field">
          <label>Tags — the grammar point, kanji reading or vocabulary group this exercises</label>
          <TagPicker
            tags={allTags}
            selected={picked}
            onToggle={(id, on) => setPicked((p) => { const n = new Set(p); if (on) n.add(id); else n.delete(id); return n; })}
            onCreated={(t) => setAllTags((ts) => [...ts, t])}
          />
        </div>
        <div className="row" style={{ gap: 22 }}>
          <Check checked={ja} onChange={setJa}>Japanese IME on</Check>
          <Check checked={active} onChange={setActive}>Active (asked by the buddy)</Check>
        </div>
        {error && <p className="error">{error}</p>}
        <div className="dialog-actions">
          <button className="btn btn-secondary" onClick={() => onClose(false)}>Cancel</button>
          <button className="btn btn-primary" disabled={busy || !prompt.trim() || answers.length === 0} onClick={save}>
            Save
          </button>
        </div>
      </div>
    </div>
  );
}
