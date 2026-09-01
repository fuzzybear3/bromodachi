-- Lesson-level switch, independent of per-question flags: the buddy asks a
-- question only when question.active AND lessons.active. Disabling a block
-- never touches question rows, so re-enabling restores the exact prior state.
alter table lessons add column active boolean not null default true;
