-- Active solve time: ms accumulated while the answer box was focused and
-- the question unanswered (gap-guarded). Wall-clock shown_at/answered_at
-- remain for comparison; null for rows recorded before this existed.
alter table attempts add column active_ms integer;
