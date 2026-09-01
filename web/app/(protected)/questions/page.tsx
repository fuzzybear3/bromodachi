"use client";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { LessonSection } from "@/components/LessonSection";
import { NewLessonForm } from "@/components/NewLessonForm";
import { QuestionEditor } from "@/components/QuestionEditor";
import type { Lesson, Question } from "@/lib/types";

export default function Questions() {
  const [lessons, setLessons] = useState<Lesson[]>([]);
  const [questions, setQuestions] = useState<Question[]>([]);
  const [editing, setEditing] = useState<Question | null | "new">(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    Promise.all([
      supabase.from("lessons").select("*").order("taught_on", { ascending: false }),
      supabase.from("questions").select("*").order("position"),
    ]).then(([l, q]) => {
      const err = l.error ?? q.error;
      if (err) return setError(err.message);
      setLessons(l.data ?? []);
      setQuestions((q.data ?? []) as Question[]);
    });
  }, []);
  useEffect(load, [load]);

  if (error) return <p className="error">{error}</p>;
  if (lessons.length === 0) return null;

  const maxPosition = (lessonId: string) =>
    Math.max(-1, ...questions.filter((q) => q.lesson_id === lessonId).map((q) => q.position));

  return (
    <>
      <p style={{ textAlign: "right", margin: "16px 0" }}>
        <button className="primary" onClick={() => setEditing("new")}>+ New question</button>
      </p>
      {lessons.map((lesson, i) => (
        <LessonSection
          key={lesson.id}
          lesson={lesson}
          questions={questions.filter((q) => q.lesson_id === lesson.id)}
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
          defaultLessonId={lessons[0].id}
          maxPosition={maxPosition}
          onClose={(saved) => {
            setEditing(null);
            if (saved) load();
          }}
        />
      )}
    </>
  );
}
