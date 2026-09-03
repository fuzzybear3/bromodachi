-- Training console (design handoff 2026-09-03): the data the review screens
-- need. Everything here is additive; nothing existing is rewritten.
--
--   questions.direction        what the learner produces from what
--   attempts.expected_text     snapshot of the accepted answer at ask time
--   attempts.ms_to_first_input recall latency (prompt -> first keystroke)
--   attempts.self_corrected    a wrong-looking intermediate was replaced
--   attempts.timing_unreliable idle/blur gap — excluded from averages
--   tags / question_tags       cross-lesson grammar/kanji/vocabulary tags
--   review_sessions            one sheet per lesson per sitting
--   reset_srs() / apply_review_session()  the two things "Apply" can do
--
-- Deliberately NOT stored: the diff between typed and expected (read-time
-- LCS), any per-question aggregate (read-time, rows number in the hundreds),
-- and "eventually correct" — the buddy records exactly one graded answer
-- per pop, so it would equal first-try; the column was dropped from the
-- design with the owner's agreement rather than shipped as a duplicate.

-- ── questions: direction ────────────────────────────────────────────────
-- ASCII keys; the web renders them with arrows. 'ja_ja' is the honest
-- value for grammar/conj prompts (Japanese in, Japanese out) — the handoff
-- had no slot for those.
alter table questions add column direction text not null default 'kanji_reading'
    check (direction in ('kanji_reading', 'reading_kanji', 'ja_en', 'en_ja', 'cloze', 'ja_ja'));

update questions set direction = case type
    when 'reading' then 'kanji_reading'
    when 'en2ja'   then 'en_ja'
    when 'cloze'   then 'cloze'
    else                'ja_ja'   -- grammar, conj
end;

-- ── attempts: the three new measurements + the snapshot ────────────────
alter table attempts
    add column expected_text text,                       -- null on pre-migration rows; read-time fallback = answers[0]
    add column ms_to_first_input int,                    -- null = not measured (old rows, skipped, or never typed)
    add column self_corrected boolean not null default false,
    add column timing_unreliable boolean not null default false;

-- ── tags ────────────────────────────────────────────────────────────────
create table tags (
    id uuid primary key default gen_random_uuid(),
    kind text not null check (kind in ('grammar', 'kanji', 'vocabulary')),
    label_ja text not null,
    label_en text,
    created_at timestamptz not null default now(),
    unique (kind, label_ja)
);

create table question_tags (
    question_id uuid not null references questions(id),
    tag_id uuid not null references tags(id),
    primary key (question_id, tag_id)
);
create index question_tags_tag_idx on question_tags (tag_id);

-- ── review sessions ─────────────────────────────────────────────────────
-- One sheet per lesson per day ("session of 2026-09-03"). Marked questions
-- and carried tags are arrays, not join tables: a sheet is a small document
-- edited by one or two people, never queried across.
create table review_sessions (
    id uuid primary key default gen_random_uuid(),
    lesson_id uuid not null references lessons(id),
    held_on date not null default current_date,
    note text not null default '',
    marked_question_ids uuid[] not null default '{}',
    tag_ids uuid[] not null default '{}',
    -- [{kind: 'reset'|'retire', target_id: uuid, enabled: bool}]
    staged_changes jsonb not null default '[]' check (jsonb_typeof(staged_changes) = 'array'),
    applied_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (lesson_id, held_on)
);
create index review_sessions_lesson_idx on review_sessions (lesson_id, held_on desc);

create trigger review_sessions_updated_at
before update on review_sessions
for each row execute function public.set_updated_at();

-- ── RLS ─────────────────────────────────────────────────────────────────
alter table tags enable row level security;
alter table question_tags enable row level security;
alter table review_sessions enable row level security;

create policy tags_select on tags for select to authenticated using (public.is_allowed());
create policy tags_insert on tags for insert to authenticated with check (public.is_allowed());
create policy tags_update on tags for update to authenticated using (public.is_allowed()) with check (public.is_allowed());

-- detaching a tag from a question is a plain delete of the link row; the
-- tag itself and the question survive, so this is the one delete policy.
create policy question_tags_select on question_tags for select to authenticated using (public.is_allowed());
create policy question_tags_insert on question_tags for insert to authenticated with check (public.is_allowed());
create policy question_tags_delete on question_tags for delete to authenticated using (public.is_allowed());

create policy review_sessions_select on review_sessions for select to authenticated using (public.is_allowed());
create policy review_sessions_insert on review_sessions for insert to authenticated with check (public.is_allowed());
create policy review_sessions_update on review_sessions for update to authenticated using (public.is_allowed()) with check (public.is_allowed());

-- ── the two mutations the web may make to the schedule ─────────────────
-- "Reset to day one" = the daemon's notion of unseen: no srs_state row.
-- Attempt history is untouched. Done as an RPC rather than a delete policy
-- so the browser still holds no general delete right on srs_state.
create function public.reset_srs(question_ids uuid[]) returns int
language plpgsql security definer
set search_path = ''
as $$
declare n int;
begin
    if not public.is_allowed() then
        raise exception 'not allowed' using errcode = '42501';
    end if;
    delete from public.srs_state where question_id = any(question_ids);
    get diagnostics n = row_count;
    return n;
end
$$;
revoke execute on function public.reset_srs(uuid[]) from anon, public;
grant execute on function public.reset_srs(uuid[]) to authenticated;

-- Apply a review sheet's staged changes in one transaction: every enabled
-- 'reset' clears the schedule, every enabled 'retire' deactivates the
-- question. Idempotent: a sheet already applied is a no-op.
create function public.apply_review_session(session_id uuid) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
    s public.review_sessions%rowtype;
    reset_ids uuid[];
    retire_ids uuid[];
    n_reset int; n_retire int;
begin
    if not public.is_allowed() then
        raise exception 'not allowed' using errcode = '42501';
    end if;
    select * into s from public.review_sessions where id = session_id for update;
    if not found then
        raise exception 'no such session';
    end if;
    if s.applied_at is not null then
        return jsonb_build_object('already_applied', true, 'applied_at', s.applied_at);
    end if;
    select coalesce(array_agg((c ->> 'target_id')::uuid), '{}') into reset_ids
      from jsonb_array_elements(s.staged_changes) c
     where c ->> 'kind' = 'reset' and (c ->> 'enabled')::boolean;
    select coalesce(array_agg((c ->> 'target_id')::uuid), '{}') into retire_ids
      from jsonb_array_elements(s.staged_changes) c
     where c ->> 'kind' = 'retire' and (c ->> 'enabled')::boolean;

    delete from public.srs_state where question_id = any(reset_ids);
    get diagnostics n_reset = row_count;
    update public.questions set active = false where id = any(retire_ids) and active;
    get diagnostics n_retire = row_count;

    update public.review_sessions set applied_at = now() where id = session_id;
    return jsonb_build_object('reset', n_reset, 'retired', n_retire);
end
$$;
revoke execute on function public.apply_review_session(uuid) from anon, public;
grant execute on function public.apply_review_session(uuid) to authenticated;
