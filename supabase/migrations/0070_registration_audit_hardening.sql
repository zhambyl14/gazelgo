-- Tasu · registration audit hardening
-- Аяқталмаған тіркелуді көру пайдалы, бірақ anonymous RPC-ге еркін JSON
-- қабылдату және жазбаларды мәңгі сақтау — көлем/құпиялылық тәуекелі.

create or replace function public.save_registration_draft(
  p_draft_key text,
  p_role text,
  p_stage integer,
  p_stage_label text,
  p_full_name text default null,
  p_phone text default null,
  p_data jsonb default '{}'::jsonb,
  p_completed boolean default false
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb;
begin
  if coalesce(length(trim(p_draft_key)), 0) not between 8 and 160
     or p_role not in ('client','executor')
     or p_stage not between 0 and 3
     or octet_length(coalesce(p_data, '{}'::jsonb)::text) > 8192 then
    raise exception 'BAD_INPUT';
  end if;

  -- Қолданбаға керек progress өрістері ғана қалады. Құпиясөздер мен еркін
  -- қосылған JSON модератор панеліне не кестеге өтіп кетпейді.
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
    into v_data
  from jsonb_each(coalesce(p_data, '{}'::jsonb))
  where key in (
    'role', 'terms_agreed', 'referral_entered', 'flow', 'city',
    'vehicle_type', 'vehicle', 'documents'
  );

  insert into public.registration_drafts
    (draft_key, role, stage, stage_label, full_name, phone, data, completed_at)
  values
    (trim(p_draft_key), p_role, p_stage, left(coalesce(p_stage_label,''), 120),
     nullif(left(trim(coalesce(p_full_name,'')), 120), ''),
     nullif(left(trim(coalesce(p_phone,'')), 32), ''),
     v_data,
     case when p_completed then now() else null end)
  on conflict (draft_key) do update set
    role = excluded.role,
    stage = excluded.stage,
    stage_label = excluded.stage_label,
    full_name = excluded.full_name,
    phone = excluded.phone,
    data = excluded.data,
    last_seen_at = now(),
    completed_at = case when p_completed then now()
                        else registration_drafts.completed_at end;
end;
$$;

-- Аяқталған audit — 30 күн, үзілгені — 90 күн: модераторға жеткілікті уақыт,
-- ал ескі телефон/көлік деректері шексіз сақталмайды.
create or replace function public.purge_registration_drafts()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  delete from public.registration_drafts
  where (completed_at is not null and completed_at < now() - interval '30 days')
     or (completed_at is null and last_seen_at < now() - interval '90 days');
end;
$$;

revoke all on function public.purge_registration_drafts() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('tasu-registration-audit-purge');
exception when others then null; end $$;

select cron.schedule(
  'tasu-registration-audit-purge',
  '17 3 * * *',
  $$select public.purge_registration_drafts();$$
);
