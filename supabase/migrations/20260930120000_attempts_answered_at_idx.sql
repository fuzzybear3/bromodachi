-- The daemon's per-pop history (last 24 h of answers, newest first) and the
-- web's timelines filter and sort on answered_at; the existing indexes are
-- on inserted_at.
create index if not exists attempts_answered_idx on attempts (answered_at desc);
create index if not exists attempts_question_answered_idx on attempts (question_id, answered_at desc);
