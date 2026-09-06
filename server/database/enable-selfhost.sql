-- Independent-server bootstrap only. Never run against the official service.
-- Client roles cannot change this setting or grant themselves entitlements.
begin;
update private.pomodoist_instance_settings
set selfhost_features_enabled = true
where singleton;
select private.grant_pomodoist_selfhost_access(id) from public.profiles;
commit;
