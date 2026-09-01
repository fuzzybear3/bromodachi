-- Bromodachi core schema: lessons, questions, attempts, srs_state, allowed_users.
-- The tables ARE the API (PostgREST); no endpoint code exists anywhere.

create table lessons (
    id uuid primary key default gen_random_uuid(),
    taught_on date not null unique,
    title text,
    created_at timestamptz not null default now()
);

create table questions (
    id uuid primary key default gen_random_uuid(),
    lesson_id uuid not null references lessons(id),
    type text not null check (type in ('reading', 'en2ja', 'grammar', 'conj')),
    prompt text not null,
    -- every accepted spelling variant (kana / kanji / romaji), grading is exact-match
    answers jsonb not null check (jsonb_typeof(answers) = 'array' and jsonb_array_length(answers) > 0),
    -- N5-Japanese hint; doubles as the "meaning" line in drill/wrong states
    hint text,
    -- false = leave the IME in English for this question
    ja boolean not null default true,
    -- soft-deactivate only; the web UI has no delete
    active boolean not null default true,
    position int not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (lesson_id, position)
);

create table attempts (
    -- no default: the id is client-generated, which makes retries idempotent
    id uuid primary key,
    question_id uuid not null references questions(id),
    shown_at timestamptz not null,
    answered_at timestamptz not null,
    correct boolean not null,
    mode text not null check (mode in ('right', 'wrong', 'drill')),
    typed text,
    hint_used boolean not null default false,
    client text not null default 'daemon',
    inserted_at timestamptz not null default now()
);

create table srs_state (
    question_id uuid primary key references questions(id),
    due_at timestamptz not null,
    interval_min double precision not null,
    ease double precision not null,
    reps int not null,
    lapses int not null,
    last_correct boolean,
    updated_at timestamptz not null
);

create table allowed_users (
    email text primary key,
    role text not null check (role in ('owner', 'teacher'))
);

create index attempts_question_inserted_idx on attempts (question_id, inserted_at desc);
create index attempts_inserted_idx on attempts (inserted_at desc);
create index questions_lesson_active_idx on questions (lesson_id) where active;
create index srs_state_due_idx on srs_state (due_at);

create function public.set_updated_at() returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end
$$;

create trigger questions_updated_at
before update on questions
for each row execute function public.set_updated_at();
