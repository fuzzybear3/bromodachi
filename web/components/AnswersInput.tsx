"use client";
import { useState } from "react";

// Chip input for answer variants. The load-bearing CJK detail: Enter during
// IME composition (kana -> kanji conversion) must NOT commit a chip, or a
// Japanese teacher cannot type at all. isComposing guards it.
export function AnswersInput({ value, onChange }: {
  value: string[];
  onChange: (answers: string[]) => void;
}) {
  const [draft, setDraft] = useState("");

  function commit() {
    const v = draft.trim();
    if (v && !value.includes(v)) onChange([...value, v]);
    setDraft("");
  }

  return (
    <div>
      <div className="chips" style={{ marginBottom: 6 }}>
        {value.map((a, i) => (
          <span className="chip" lang="ja" key={`${a}-${i}`}>
            {a}
            <button type="button" aria-label={`remove ${a}`}
                    onClick={() => onChange(value.filter((_, j) => j !== i))}>
              ×
            </button>
          </span>
        ))}
      </div>
      <input
        className="input" type="text" lang="ja" value={draft}
        placeholder="type a variant, Enter to add (kana / kanji / romaji)"
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            if (!e.nativeEvent.isComposing) commit();
          } else if (e.key === "Backspace" && draft === "" && value.length > 0) {
            onChange(value.slice(0, -1));
          }
        }}
        onBlur={commit}
      />
    </div>
  );
}
