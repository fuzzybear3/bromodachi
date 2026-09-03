"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { Blueprint } from "./ui";

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
    <Blueprint className="pad-18">
      <h6 style={{ margin: 0 }}>New lesson</h6>
      <div className="form-row" style={{ alignItems: "flex-end" }}>
        <div className="field">
          <label>Date taught</label>
          <input className="input" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </div>
        <div className="field">
          <label>Title (optional)</label>
          <input className="input" type="text" lang="ja" value={title} onChange={(e) => setTitle(e.target.value)} />
        </div>
        <div style={{ flex: "0 0 auto" }}>
          <button className="btn btn-primary" disabled={!date} onClick={add}>Add lesson</button>
        </div>
      </div>
      {error && <p className="error">{error}</p>}
    </Blueprint>
  );
}
