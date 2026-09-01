"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase/client";

export function NewLessonForm({ onCreated }: { onCreated: () => void }) {
  const [date, setDate] = useState("");
  const [title, setTitle] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function add() {
    setError(null);
    const { error } = await supabase.from("lessons")
      .insert({ taught_on: date, title: title.trim() || null });
    if (error) {
      setError(error.code === "23505"
        ? "A lesson for that date already exists."
        : error.message);
    } else {
      setDate("");
      setTitle("");
      onCreated();
    }
  }

  return (
    <div className="panel">
      <h2>New lesson</h2>
      <div className="row">
        <div>
          <label>Date taught</label>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </div>
        <div>
          <label>Title (optional)</label>
          <input type="text" lang="ja" value={title} onChange={(e) => setTitle(e.target.value)} />
        </div>
        <div style={{ flex: "0 0 auto" }}>
          <button className="primary" disabled={!date} onClick={add}>Add lesson</button>
        </div>
      </div>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
