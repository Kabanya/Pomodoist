begin;

update public.quota_definitions
set limit_value = 2500
where app_id = 'pomodoist' and quota_key = 'voice_transcriptions';

-- Apply the new limit to the current month without resetting recorded usage.
update public.usage_periods
set limit_value = 2500
where app_id = 'pomodoist' and quota_key = 'voice_transcriptions'
  and period_start <= now() and period_end > now();

commit;
