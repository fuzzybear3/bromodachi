-- is_allowed() exists solely for RLS policy checks by the authenticated
-- role; nothing should call it over RPC as anon.
revoke execute on function public.is_allowed() from anon, public;
