"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { Check } from "./ui";
import type { Tag, TagKind } from "@/lib/types";

const KINDS: TagKind[] = ["grammar", "kanji", "vocabulary"];

// Tags cut across lessons; a question carries many. This sits inside the
// question editor: tick existing tags, or create one inline (it is saved
// immediately — a tag is harmless on its own).
export function TagPicker({ tags, selected, onToggle, onCreated }: {
  tags: Tag[];
  selected: Set<string>;
  onToggle: (id: string, on: boolean) => void;
  onCreated: (t: Tag) => void;
}) {
  const [kind, setKind] = useState<TagKind>("grammar");
  const [ja, setJa] = useState("");
  const [en, setEn] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function create() {
    const { data, error } = await supabase
      .from("tags")
      .insert({ kind, label_ja: ja.trim(), label_en: en.trim() || null })
      .select("*")
      .single();
    if (error) return setError(error.message);
    onCreated(data as Tag);
    onToggle((data as Tag).id, true);
    setJa("");
    setEn("");
  }

  return (
    <div className="stack" style={{ gap: 8 }}>
      {KINDS.map((k) => {
        const of = tags.filter((t) => t.kind === k);
        if (of.length === 0) return null;
        return (
          <div key={k} className="tag-pick">
            <span className="card-kicker" style={{ width: 80 }}>{k}</span>
            {of.map((t) => (
              <Check key={t.id} checked={selected.has(t.id)} onChange={(on) => onToggle(t.id, on)}>
                <span lang="ja">{t.label_ja}</span>
                {t.label_en && <span className="muted small"> · {t.label_en}</span>}
              </Check>
            ))}
          </div>
        );
      })}
      <div className="form-row" style={{ alignItems: "flex-end" }}>
        <div className="field" style={{ flex: "0 0 120px" }}>
          <label>new tag</label>
          <select className="input" value={kind} onChange={(e) => setKind(e.target.value as TagKind)}>
            {KINDS.map((k) => <option key={k}>{k}</option>)}
          </select>
        </div>
        <div className="field"><label>Japanese</label>
          <input className="input" lang="ja" value={ja} onChange={(e) => setJa(e.target.value)} placeholder="促音" /></div>
        <div className="field"><label>English gloss</label>
          <input className="input" value={en} onChange={(e) => setEn(e.target.value)} placeholder="small tsu" /></div>
        <button type="button" className="btn btn-secondary" disabled={!ja.trim()} onClick={create}>Add tag</button>
      </div>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
