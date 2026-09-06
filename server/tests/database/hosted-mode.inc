-- Payment and projection regression tests run with local grants disabled.
-- The surrounding test transaction restores the operator setting on rollback.
do $$
begin
  if to_regclass('private.pomodoist_instance_settings') is not null then
    update private.pomodoist_instance_settings set selfhost_features_enabled = false;
  end if;
end;
$$;
