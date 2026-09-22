-- Read-only application catalog fingerprint. Excludes data, statistics and api_v1.
with objects as (
  select 'function:'||p.oid::regprocedure::text as key,
    jsonb_build_array(pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.proacl::text) as value
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private','billing') and p.prokind='f'
  union all
  select 'relation:'||n.nspname||'.'||c.relname,
    jsonb_build_array(c.relkind,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner),c.relacl::text)
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private','billing') and c.relkind in ('r','p','v','m','S')
  union all
  select 'column:'||n.nspname||'.'||c.relname||'.'||a.attname,
    jsonb_build_array(format_type(a.atttypid,a.atttypmod),a.attnotnull,pg_get_expr(d.adbin,d.adrelid),a.attidentity,a.attgenerated)
  from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
  left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
  where n.nspname in ('public','private','billing') and a.attnum>0 and not a.attisdropped and c.relkind in ('r','p','v','m')
  union all
  select 'constraint:'||n.nspname||'.'||c.relname||'.'||con.conname,to_jsonb(pg_get_constraintdef(con.oid))
  from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private','billing')
  union all
  select 'index:'||schemaname||'.'||indexname,to_jsonb(indexdef) from pg_indexes
  where schemaname in ('public','private','billing')
  union all
  select 'policy:'||schemaname||'.'||tablename||'.'||policyname,to_jsonb(p) from pg_policies p
  where schemaname in ('public','private','billing')
  union all
  select 'trigger:'||n.nspname||'.'||c.relname||'.'||t.tgname,to_jsonb(pg_get_triggerdef(t.oid))
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private','billing') and not t.tgisinternal
)
select md5(jsonb_object_agg(key,value order by key)::text) as fingerprint from objects;
