-- ============================================================
-- Tasu · 0084_support_staff.sql
-- ============================================================
-- ҚОЛДАУ ҚЫЗМЕТКЕРЛЕРІ: модератор телефон + құпиясөзбен қызметкер
-- аккаунтын ашады да, оған панельдің қай бөлімдері ашық болатынын
-- белгілейді (кейін қосып/алып тастай алады).
--
--   * profiles.staff_perms — NULL болса: ТОЛЫҚ модератор (бұрынғыдай,
--     бәріне рұқсат). Массив болса: қызметкер, тек тізімдегі бөлімдер.
--     Қызметкердің role-ы да 'moderator' — сондықтан бұрынғы RLS пен
--     RPC-лер оған өзгеріссіз жұмыс істейді, ал шектеуді екі қабат
--     ұстайды: (1) қосымша рұқсатсыз бөлімді мәзірде көрсетпейді;
--     (2) СЕРВЕР: PostgREST pre-request функциясы рұқсатсыз mod_* RPC-ні
--     және баптау/жаңалық/көлік кестелеріне жазуды бұғаттайды.
--   * Қызметкерді ашу / құпиясөз / өшіру — `staff-admin` edge функциясы
--     (auth.users-ке тек service-role кілтімен жазылады).
--   * Тізім мен рұқсаттарды өзгерту — mod_staff_list / mod_staff_set_perms,
--     ТЕК толық модератор (қызметкер өзіне рұқсат бере алмайды).
--
-- Рұқсат кілттері (қосымшадағы StaffPerm-мен бірдей):
--   overview, line, live_map, orders, applications, executors, clients,
--   balance, topups, support, reports, order_chats, broadcast, news,
--   vehicles, settings, audit
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0083-тен кейін).
-- ============================================================

alter table public.profiles add column if not exists staff_perms text[];

comment on column public.profiles.staff_perms is
  'NULL = толық модератор; массив = қолдау қызметкері, тек осы бөлімдер (0084)';

-- Барлық рұқсат кілттері — бір жерде.
create or replace function public.staff_perm_keys()
returns text[]
language sql immutable
as $$
  select array[
    'overview','line','live_map','orders','applications','executors',
    'clients','balance','topups','support','reports','order_chats',
    'broadcast','news','vehicles','settings','audit'
  ]::text[];
$$;

-- Толық модератор (қызметкер ЕМЕС).
create or replace function public.is_full_moderator()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'moderator' and staff_perms is null
  );
$$;

-- Модератор/қызметкердің осы бөлімге рұқсаты бар ма.
create or replace function public.mod_can(p_perm text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'moderator'
      and (staff_perms is null or p_perm = any(staff_perms))
  );
$$;

-- ------------------------------------------------------------
-- staff_perms-ті клиенттен тікелей UPDATE-пен өзгертуге болмайды
-- (тек SECURITY DEFINER RPC / service-role).
-- ------------------------------------------------------------
create or replace function public.guard_staff_perms()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user in ('postgres','service_role','supabase_admin') then
    return new;
  end if;
  if new.staff_perms is distinct from old.staff_perms then
    raise exception 'FORBIDDEN_COLUMN';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_staff_perms on public.profiles;
create trigger trg_guard_staff_perms
  before update on public.profiles
  for each row execute function public.guard_staff_perms();

-- ------------------------------------------------------------
-- Қызметкерлер тізімі (тек толық модератор)
-- ------------------------------------------------------------
create or replace function public.mod_staff_list()
returns jsonb
language plpgsql stable security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.is_full_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', p.id,
             'full_name', p.full_name,
             'phone', p.phone,
             'perms', to_jsonb(p.staff_perms),
             'disabled', p.blocked_at is not null,
             'created_at', p.created_at,
             'last_sign_in_at', u.last_sign_in_at
           ) order by p.created_at desc)
    from public.profiles p
    left join auth.users u on u.id = p.id
    where p.role = 'moderator' and p.staff_perms is not null
  ), '[]'::jsonb);
end;
$$;

-- ------------------------------------------------------------
-- Қызметкердің рұқсаттарын өзгерту (тек толық модератор)
-- ------------------------------------------------------------
create or replace function public.mod_staff_set_perms(p_user uuid, p_perms text[])
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_clean text[];
begin
  if not public.is_full_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  -- Белгісіз кілттерді лақтырамыз, қайталанғанын біріктіреміз.
  select coalesce(array_agg(distinct k order by k), '{}')
    into v_clean
    from unnest(coalesce(p_perms, '{}')) k
   where k = any(public.staff_perm_keys());

  update public.profiles
     set staff_perms = v_clean
   where id = p_user and role = 'moderator' and staff_perms is not null;
  if not found then
    raise exception 'NOT_STAFF';
  end if;

  perform public.mod_audit('staff_perms', 'staff', p_user::text,
                           jsonb_build_object('perms', to_jsonb(v_clean)));
end;
$$;

revoke all on function public.mod_staff_list() from public, anon;
revoke all on function public.mod_staff_set_perms(uuid, text[]) from public, anon;
grant execute on function public.mod_staff_list() to authenticated;
grant execute on function public.mod_staff_set_perms(uuid, text[]) to authenticated;
grant execute on function public.is_full_moderator() to authenticated;
grant execute on function public.mod_can(text) to authenticated;

-- ------------------------------------------------------------
-- СЕРВЕРЛІК ШЕКТЕУ: PostgREST pre-request.
--
-- Әр API сұранысының алдында орындалады. Тек «қорғалған» жолдарда
-- (mod_* RPC, баптау/жаңалық/көлік кестелеріне жазу, журнал оқу) ғана
-- профильге қарайды, қалғаны бірден өтеді. Толық модератор мен
-- қарапайым қолданушыға ешқандай әсері жоқ — тек қызметкерге.
--
-- ҚАУІПСІЗДІК: функция ішіндегі кез келген күтпеген қате сұранысты
-- бұзбайды (тек NO_PERMISSION ғана лақтырылады) — әйтпесе бүкіл API
-- тоқтап қалуы мүмкін еді.
-- ------------------------------------------------------------
create or replace function public.staff_request_guard()
returns void
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_path   text;
  v_method text;
  v_need   text[];
  v_perms  text[];
  v_blocked boolean := false;
  v_deny   boolean := false;
begin
  begin
    v_path := coalesce(current_setting('request.path', true), '');
    v_method := upper(coalesce(current_setting('request.method', true), ''));

    if v_path like '/rpc/%' then
      v_need := case substr(v_path, 6)
        when 'mod_dashboard_series'     then array['overview']
        when 'mod_line_stats'           then array['line']
        when 'mod_live_map'             then array['live_map']
        when 'mod_set_order_status'     then array['orders','line','live_map','reports','support','executors','clients','order_chats']
        when 'mod_cancel_order'         then array['orders','line','live_map','reports','support','executors','clients','order_chats']
        when 'mod_reopen_order'         then array['orders','line','live_map','reports','support','executors','clients','order_chats']
        when 'mod_approve_docs'         then array['applications']
        when 'mod_reject_docs'          then array['applications']
        when 'mod_set_executor_status'  then array['applications','executors']
        when 'mod_request_docs'         then array['applications','executors']
        when 'mod_executor_summary'     then array['applications','executors']
        when 'mod_registration_drafts'  then array['applications','executors','clients']
        when 'mod_adjust_balance'       then array['balance']
        when 'mod_set_account_blocked'  then array['executors','clients','reports','support']
        when 'mod_adjust_trust_score'   then array['executors','clients','reports','support']
        when 'mod_review_topup'         then array['topups']
        when 'topup_reconciliation'     then array['topups']
        when 'mod_set_report_status'    then array['reports']
        when 'mod_listing_reports'      then array['reports']
        when 'mod_resolve_listing_report' then array['reports']
        when 'mod_listings'             then array['reports']
        when 'mod_order_chats'          then array['order_chats']
        when 'mod_pending_support_images' then array['support']
        when 'mod_broadcast'            then array['broadcast']
        when 'mod_news_list'            then array['news']
        when 'mod_news_save'            then array['news']
        when 'mod_news_delete'          then array['news']
        when 'mod_news_reorder'         then array['news']
        when 'mod_vehicle_types'        then array['vehicles']
        when 'mod_save_vehicle_type'    then array['vehicles']
        when 'mod_delete_vehicle_type'  then array['vehicles']
        when 'mod_reorder_vehicle_types' then array['vehicles']
        when 'mod_update_setting'       then array['settings']
        when 'mod_bonus_stats'          then array['settings']
        else null end;
    elsif v_method in ('POST','PATCH','PUT','DELETE') then
      v_need := case ltrim(v_path, '/')
        when 'app_settings'  then array['settings']
        when 'news'          then array['news']
        when 'vehicle_types' then array['vehicles']
        else null end;
    elsif ltrim(v_path, '/') = 'mod_audit_log' then
      v_need := array['audit'];
    end if;

    if v_need is null then
      return;
    end if;

    select p.staff_perms, p.blocked_at is not null
      into v_perms, v_blocked
      from public.profiles p
     where p.id = auth.uid() and p.role = 'moderator';

    -- Толық модератор (NULL) немесе мүлдем модератор емес — тиіспейміз
    -- (модератор еместі RPC-лердің өзі бұрынғыдай FORBIDDEN қылады).
    if v_perms is null then
      return;
    end if;
    v_deny := v_blocked or not (v_perms && v_need);
  exception when others then
    return;
  end;

  if v_deny then
    raise exception 'NO_PERMISSION' using errcode = '42501';
  end if;
end;
$$;

grant execute on function public.staff_request_guard() to anon, authenticated, service_role;

-- PostgREST-ке осы функцияны әр сұраныс алдында шақыруды айтамыз.
do $$
begin
  alter role authenticator set pgrst.db_pre_request = 'public.staff_request_guard';
exception when others then
  raise notice 'pre-request орнатылмады: % (сервер шектеуі өшік, қосымшадағы шектеу жұмыс істейді)', sqlerrm;
end;
$$;

notify pgrst, 'reload config';
