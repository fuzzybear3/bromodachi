// Hand-written row types (no codegen toolchain; if the schema churns,
// mcp generate_typescript_types can regenerate in one shot).
export interface Lesson {
  id: string;
  taught_on: string;
  title: string | null;
  active: boolean;
  created_at: string;
}

export type QuestionType = "reading" | "en2ja" | "grammar" | "conj" | "cloze";

// What the learner produces from what. ASCII keys in the DB; arrows in the
// UI (see format.ts). ja_ja = grammar/conj prompts, Japanese in and out.
export type Direction = "kanji_reading" | "reading_kanji" | "ja_en" | "en_ja" | "cloze" | "ja_ja";

export interface Question {
  id: string;
  lesson_id: string;
  type: QuestionType;
  direction: Direction;
  prompt: string;
  answers: string[];
  hint: string | null;
  ja: boolean;
  active: boolean;
  position: number;
  created_at: string;
  updated_at: string;
}

export interface Attempt {
  id: string;
  question_id: string;
  shown_at: string;
  answered_at: string;
  correct: boolean;
  mode: string;
  typed: string | null;
  hint_used: boolean;
  active_ms: number | null;
  // training-console fields (2026-09-03); null/false on older rows
  expected_text: string | null;
  ms_to_first_input: number | null;
  self_corrected: boolean;
  timing_unreliable: boolean;
  inserted_at: string;
}

export interface SrsState {
  question_id: string;
  due_at: string;
  interval_min: number;
  ease: number;
  reps: number;
  lapses: number;
  last_correct: boolean | null;
  updated_at: string;
}

export type TagKind = "grammar" | "kanji" | "vocabulary";

export interface Tag {
  id: string;
  kind: TagKind;
  label_ja: string;
  label_en: string | null;
  created_at: string;
}

export interface QuestionTag {
  question_id: string;
  tag_id: string;
}

// The two things Apply can actually do; anything else a session decides
// on lives in the note as text.
export type StagedChange = { kind: "reset" | "retire"; target_id: string; enabled: boolean };

export interface ReviewSession {
  id: string;
  lesson_id: string;
  held_on: string;
  note: string;
  marked_question_ids: string[];
  tag_ids: string[];
  staged_changes: StagedChange[];
  applied_at: string | null;
  created_at: string;
  updated_at: string;
}

export type Role = "owner" | "teacher";
