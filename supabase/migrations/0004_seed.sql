-- GazelGo · 0004_seed.sql
-- Баптаулар, storage бакеттері + саясаттары, realtime, pg_cron, модератор аккаунты.

-- ---------- баптаулар ----------
insert into public.app_settings (key, value) values
  ('tariffs', '{"simple_day": 400, "vip_day": 800, "night_discount": 0.5}'),
  ('instant_pricing', '{
     "small":  {"base": 2500, "per_km": 250, "min": 3000},
     "medium": {"base": 3500, "per_km": 300, "min": 4500},
     "large":  {"base": 5000, "per_km": 350, "min": 6500}
   }'),
  ('payment', '{"kaspi_number": "+7 777 000 0000", "kaspi_name": "Tasu", "min_topup": 500}'),
  ('shift', '{"day_start": 8, "day_end": 20, "tz": "Asia/Almaty"}')
on conflict (key) do update set value = excluded.value;

-- ---------- storage ----------
insert into storage.buckets (id, name, public)
values ('docs', 'docs', false), ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- docs: әркім өз папкасына (uid/...) жазады, өзінікін + модератор көреді
drop policy if exists "docs_insert_own" on storage.objects;
create policy "docs_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'docs' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "docs_select_own_or_mod" on storage.objects;
create policy "docs_select_own_or_mod" on storage.objects
  for select to authenticated
  using (bucket_id = 'docs'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_moderator()));

drop policy if exists "docs_update_own" on storage.objects;
create policy "docs_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'docs' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "docs_delete_own" on storage.objects;
create policy "docs_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'docs' and (storage.foldername(name))[1] = auth.uid()::text);

-- avatars: көпшілікке ашық оқу, өз папкасына жазу
drop policy if exists "avatars_select_all" on storage.objects;
create policy "avatars_select_all" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------- realtime ----------
do $$ begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.offers;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.vip_dispatches;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.topup_requests;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.executor_profiles;
exception when duplicate_object then null; end $$;

-- ---------- pg_cron ----------
create extension if not exists pg_cron;

do $$ begin
  perform cron.unschedule('gazelgo-vip-advance');
exception when others then null; end $$;
select cron.schedule('gazelgo-vip-advance', '10 seconds', $$select public.advance_all_vip()$$);

do $$ begin
  perform cron.unschedule('gazelgo-expire-orders');
exception when others then null; end $$;
select cron.schedule('gazelgo-expire-orders', '*/5 * * * *', $$select public.expire_stale_orders()$$);

-- ---------- модератор аккаунты ----------
-- Кіру: телефон +7 700 000 00 01, құпиясөз GazelGo#2026
-- (бірінші кіргеннен кейін құпиясөзді ауыстырыңыз! Аккаунт қалғандай телефон
-- ағынымен бірдей синтетикалық email арқылы құрылады — 0015-те phone.dart-пен
-- сәйкес keлуі шарт.)
do $$
declare
  v_id uuid := gen_random_uuid();
  v_email text := '77000000001@phone.gazelgo.kz';
begin
  if not exists (select 1 from auth.users where email = v_email) then
    insert into auth.users
      (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
       raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
       confirmation_token, recovery_token, email_change, email_change_token_new)
    values
      (v_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       v_email, crypt('GazelGo#2026', gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}',
       '{"full_name":"Модератор","phone":"77000000001"}',
       now(), now(), '', '', '', '');

    insert into auth.identities
      (id, user_id, provider_id, identity_data, provider,
       last_sign_in_at, created_at, updated_at)
    values
      (gen_random_uuid(), v_id, v_id::text,
       jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
       'email', now(), now(), now());

    update public.profiles
       set role = 'moderator', full_name = 'Модератор', phone = '77000000001'
     where id = v_id;
  end if;
end $$;
