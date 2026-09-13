begin;

-- Match the UTC calendar used by quota enforcement even when a connection uses
-- another timezone. Preserve each installation's reader bodies and privileges.
alter function public.get_usage_period(text,text,timestamptz,timestamptz)
  set timezone = 'UTC';
alter function public.get_account_overview() set timezone = 'UTC';

commit;
