// Hand-written row types for the five tables (no codegen toolchain; if the
// schema churns, mcp generate_typescript_types can regenerate in one shot).
export interface Lesson {
  id: string;
  taught_on: string;
  title: string | null;
  active: boolean;
  created_at: string;
}

export type QuestionType = "reading" | "en2ja" | "grammar" | "conj";

export interface Question {
  id: string;
  lesson_id: string;
  type: QuestionType;
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

export type Role = "owner" | "teacher";
