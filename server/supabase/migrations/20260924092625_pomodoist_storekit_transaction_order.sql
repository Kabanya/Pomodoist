-- Existing notification rows stored the envelope date as latest_signed_at.
-- Restore the timestamp of the signed transaction used by the purchase RPC.
update public.pomodoist_purchase_claims
set latest_signed_at = to_timestamp(
  (raw_claims ->> 'signedDate')::double precision / 1000
)
where jsonb_typeof(raw_claims -> 'signedDate') = 'number'
  and (raw_claims ->> 'signedDate') ~ '^[0-9]{12,16}$';
