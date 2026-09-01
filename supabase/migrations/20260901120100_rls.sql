-- RLS: web users (authenticated) are gated by the allowed_users allowlist.
-- The daemon uses the project secret key (service role) and bypasses RLS.

alter table lessons enable row level security;
alter table questions enable row level security;
alter table attempts enable row level security;
alter table srs_state enable row level security;
alter table allowed_users enable row level security;

-- security definer breaks the chicken-and-egg of reading allowed_users
-- from inside its own gate; search_path pinned per advisor guidance.
create function public.is_allowed() returns boolean
language sql stable security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.allowed_users
        where email = (select auth.jwt() ->> 'email')
    )
$$;

-- lessons & questions: read + write for allowed users. Deliberately NO
-- delete policy: soft-deactivate (questions.active) is the only web path,
-- so attempt history can never be orphaned from the browser.
create policy lessons_select on lessons for select to authenticated using (public.is_allowed());
create policy lessons_insert on lessons for insert to authenticated with check (public.is_allowed());
create policy lessons_update on lessons for update to authenticated using (public.is_allowed()) with check (public.is_allowed());

create policy questions_select on questions for select to authenticated using (public.is_allowed());
create policy questions_insert on questions for insert to authenticated with check (public.is_allowed());
create policy questions_update on questions for update to authenticated using (public.is_allowed()) with check (public.is_allowed());

-- history and srs are daemon-written; the web only reads them
create policy attempts_select on attempts for select to authenticated using (public.is_allowed());
create policy srs_state_select on srs_state for select to authenticated using (public.is_allowed());

-- each signed-in user may read exactly their own allowlist row
create policy allowed_users_self on allowed_users for select to authenticated
    using (email = (select auth.jwt() ->> 'email'));
