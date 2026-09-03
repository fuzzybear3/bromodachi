"use client";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { LessonSection } from "@/components/LessonSection";
import { NewLessonForm } from "@/components/NewLessonForm";
import { QuestionEditor } from "@/components/QuestionEditor";
import { tagsByQuestion } from "@/lib/agg";
import type { Lesson, Question, QuestionTag, Tag } from "@/lib/types";

export default function Questions() {
  const [lessons, setLessons] = useState<Lesson[]>([]);
  const [questions, setQuestions] = useState<Question[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [links, setLinks] = useState<QuestionTag[]>([]);
  const [editing, setEditing] = useState<Question | null | "new">(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    Promise.all([
      supabase.from("lessons").select("*").order("taught_on", { ascending: false }),
      supabase.from("questions").select("*").order("position"),
      supabase.from("tags").select("*").order("label_ja"),
      supabase.from("question_tags").select("*"),
    ]).then(([l, q, t, qt]) => {
      const err = l.error ?? q.error ?? t.error ?? qt.error;
      if (err) return setError(err.message);
      setLessons(l.data ?? []);
      setQuestions((q.data ?? []) as Question[]);
      setTags((t.data ?? []) as Tag[]);
      setLinks((qt.data ?? []) as QuestionTag[]);
    });
  }, []);
  useEffect(load, [load]);

  if (error) return <p className="error">{error}</p>;
  if (lessons.length === 0) return null;

  const byQ = tagsByQuestion(links, tags);
  const maxPosition = (lessonId: string) =>
    Math.max(-1, ...questions.filter((q) => q.lesson_id === lessonId).map((q) => q.position));

  return (
    <div className="page">
      <div className="row end">
        <h4 style={{ margin: 0 }}>Question bank</h4>
        <span className="tag tag-neutral">{lessons.length} lessons · {questions.length} questions</span>
        <span className="spacer" />
        <button className="btn btn-primary" onClick={() => setEditing("new")}>+ New question</button>
      </div>
      {lessons.map((lesson, i) => (
        <LessonSection
          key={lesson.id}
          lesson={lesson}
          questions={questions.filter((q) => q.lesson_id === lesson.id)}
          tagsByQuestion={byQ}
          open={i === 0}
          onEdit={setEditing}
          onChanged={load}
        />
      ))}
      <NewLessonForm onCreated={load} />
      {editing !== null && (
        <QuestionEditor
          question={editing === "new" ? null : editing}
          lessons={lessons}
          tags={tags}
          questionTagIds={editing === "new" ? [] : (byQ.get(editing.id) ?? []).map((t) => t.id)}
          defaultLessonId={lessons[0].id}
          maxPosition={maxPosition}
          onClose={(saved) => {
            setEditing(null);
            if (saved) load();
          }}
        />
      )}
    </div>
  );
}
