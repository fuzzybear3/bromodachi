-- New question type: fill-in-the-blank. Prompt carries the sentence with
-- ＿＿ and an English cue; the answer is just the missing piece, so cloze
-- items test grammar points without full-sentence typing time.
alter table questions drop constraint questions_type_check;
alter table questions add constraint questions_type_check
    check (type in ('reading', 'en2ja', 'grammar', 'conj', 'cloze'));
