-- ============================================================
-- Tasu · 0081_review_tags.sql
-- ============================================================
-- БАҒАЛАУ ТЕГТЕРІ: жұлдыздан бөлек «не ұнады / не ұнамады».
--
-- Бұрын бағалау тек 1–5 жұлдыз + еркін мәтін еді: «4 жұлдыз» — неге 4?
-- Енді бір басумен нақты тег: «Уақтылы», «Жүкке ұқыпты», «Сыпайы» /
-- «Кешікті», «Жүкті бүлдірді»… Профильде олардың жиынтығы көрінеді
-- («Уақтылы ×12») — келесі клиент таңдағанда пайдалы.
--
-- Тегтер ТҰРАҚТЫ КОДПЕН сақталады (аудармасы қосымшада), рұқсат етілген
-- тізімнен тыс код елеусіз қалады.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0080-ден кейін).
-- ============================================================

alter table public.reviews add column if not exists tags text[] not null default '{}';

drop function if exists public.submit_review(uuid, int, text);

create or replace function public.submit_review(
  p_order uuid,
  p_rating int,
  p_comment text default '',
  p_tags text[] default '{}')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_role public.user_role;
  v_target uuid;
  v_tags text[];
  c_allowed constant text[] := array[
    -- оң
    'punctual', 'careful', 'polite', 'helpful', 'clean_car', 'clear_info',
    'ready_on_time',
    -- теріс
    'late', 'rude', 'damaged', 'overpriced', 'long_wait', 'wrong_info'
  ];
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'BAD_RATING'; end if;

  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.status <> 'completed' then raise exception 'NOT_COMPLETED'; end if;
  if o.executor_id is null then raise exception 'NOT_FOUND'; end if;

  if v_uid = o.client_id then
    v_role := 'client'; v_target := o.executor_id;
  elsif v_uid = o.executor_id then
    v_role := 'executor'; v_target := o.client_id;
  else
    raise exception 'FORBIDDEN';
  end if;

  if exists (select 1 from public.reviews where order_id = p_order and author_role = v_role) then
    raise exception 'ALREADY_REVIEWED';
  end if;

  select coalesce(array_agg(distinct t), '{}') into v_tags
    from unnest(coalesce(p_tags, '{}')) as t
   where t = any (c_allowed);

  insert into public.reviews
    (order_id, client_id, executor_id, author_role, author_id, target_id,
     rating, comment, tags)
  values
    (p_order, o.client_id, o.executor_id, v_role, v_uid, v_target,
     p_rating, coalesce(trim(p_comment),''), v_tags[1:6]);

  perform public.recompute_rating(v_target);
end;
$$;

grant execute on function public.submit_review(uuid, int, text, text[]) to authenticated;

-- ============================================================
-- Адамның алған тегтерінің жиынтығы (профиль, ұсыныс карточкасы)
-- ============================================================
-- p_role — адамның БАҒАЛАНҒАН рөлі: 'executor' (клиенттер берген тегтер)
-- не 'client' (орындаушылар берген тегтер).
create or replace function public.user_review_tags(p_user uuid, p_role text default 'executor')
returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_object_agg(tag, cnt), '{}'::jsonb)
    from (
      select t as tag, count(*) as cnt
        from public.reviews r, unnest(r.tags) as t
       where r.target_id = p_user
         and r.author_role::text = case when p_role = 'client'
                                        then 'executor' else 'client' end
       group by t
    ) s;
$$;

grant execute on function public.user_review_tags(uuid, text) to anon, authenticated;
