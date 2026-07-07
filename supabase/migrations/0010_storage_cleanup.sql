-- 0010: қолданылмайтын суреттерді Storage-тан тазалау (қолдау чат суреттері).
-- Жабылған чат тредтерінің суреттерін модератор сессиясы кезінде жинап,
-- клиент жағы storage.remove() шақырады (SQL Storage файлдарды тікелей өшіре алмайды).

alter table public.support_threads
  add column if not exists images_cleaned boolean not null default false;

create or replace function public.mod_pending_support_images()
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_paths text[];
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'moderator' then
    raise exception 'FORBIDDEN';
  end if;

  select coalesce(array_agg(m.image_path), '{}')
    into v_paths
  from public.support_messages m
  join public.support_threads t on t.id = m.thread_id
  where t.status = 'closed'
    and t.images_cleaned = false
    and m.image_path is not null;

  update public.support_threads
  set images_cleaned = true
  where status = 'closed' and images_cleaned = false;

  return v_paths;
end;
$$;

grant execute on function public.mod_pending_support_images() to authenticated;
