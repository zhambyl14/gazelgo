-- Tasu · 0033_docs_update_storage_cleanup.sql
-- Модератор орындаушыдан белгілі бір құжатты (мыс. паспортты) қайта
-- жүктеуді сұраса (mod_request_docs → submit_docs_update), ЕСКІ файл
-- Storage-та ЕШҚАШАН өшірілмейтін — тек DB көрсеткіші жаңа файлға
-- ауысатын, ескі объект мәңгі "орфан" болып қалатын еді. (Ескертпе: жаңа
-- өтінім/қайта тіркелу жолы — submitExecutorApplication/lib/core/
-- repo.dart:319-372 — бұны бұрыннан дұрыс істейтін, тек осы "модератор
-- сұрағанда жаңарту" жолы ғана ақаулы болатын.)
--
-- Сонымен қатар 0023-те регрессия бар екен: `p_photos` (көлік фотолары)
-- параметрі қабылданғанмен, UPDATE-тің SET тізімінде `vehicle_photos =`
-- жолы жоқ болып қалып қойған — яғни модератор көлік фотосын қайта
-- сұраса, жаңа фото Storage-қа жүктеліп, бірақ БАЗАҒА ЕШҚАШАН ЖАЗЫЛМАЙТЫН
-- (0014-те дұрыс болатын, 0023 оны жоғалтқан). Осы миграция соны да
-- қалпына келтіреді.
--
-- Енді функция ауыстырылған ескі жолдарды (`text[]`) қайтарады — клиент
-- жағы (lib/core/repo.dart, Repo.submitDocsUpdate) соны storage.remove()
-- арқылы өшіреді.

drop function if exists public.submit_docs_update(text,text,text,text[],text,text,text,text,text);

create function public.submit_docs_update(
  p_id_doc text default null,
  p_license text default null,
  p_tech text default null,
  p_photos text[] default null,
  p_id_selfie text default null,
  p_license_selfie text default null,
  p_passport text default null,
  p_passport_selfie text default null,
  p_tech_selfie text default null)
returns text[]
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  ep public.executor_profiles;
  v_old text[] := '{}';
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;

  select * into ep from public.executor_profiles where user_id = auth.uid();
  if not found then raise exception 'NOT_EXECUTOR'; end if;

  -- нақты АУЫСТЫРЫЛҒАН (жаңа мән ескіден өзгеше, ескісі бос емес) жолдар
  -- ғана "ескі" деп есептеледі — тимегенін (сол бұрынғы жолын қайта
  -- жіберсе) жоймаймыз.
  if p_id_doc is not null and ep.id_doc_path is not null and p_id_doc <> ep.id_doc_path then
    v_old := v_old || ep.id_doc_path;
  end if;
  if p_license is not null and ep.license_path is not null and p_license <> ep.license_path then
    v_old := v_old || ep.license_path;
  end if;
  if p_tech is not null and ep.tech_passport_path is not null and p_tech <> ep.tech_passport_path then
    v_old := v_old || ep.tech_passport_path;
  end if;
  if p_tech_selfie is not null and ep.tech_passport_selfie_path is not null
     and p_tech_selfie <> ep.tech_passport_selfie_path then
    v_old := v_old || ep.tech_passport_selfie_path;
  end if;
  if p_id_selfie is not null and ep.id_selfie_path is not null and p_id_selfie <> ep.id_selfie_path then
    v_old := v_old || ep.id_selfie_path;
  end if;
  if p_license_selfie is not null and ep.license_selfie_path is not null
     and p_license_selfie <> ep.license_selfie_path then
    v_old := v_old || ep.license_selfie_path;
  end if;
  if p_passport is not null and ep.passport_path is not null and p_passport <> ep.passport_path then
    v_old := v_old || ep.passport_path;
  end if;
  if p_passport_selfie is not null and ep.passport_selfie_path is not null
     and p_passport_selfie <> ep.passport_selfie_path then
    v_old := v_old || ep.passport_selfie_path;
  end if;
  if p_photos is not null and ep.vehicle_photos is not null then
    v_old := v_old || coalesce(
      (select array_agg(x) from unnest(ep.vehicle_photos) x where x <> all(p_photos)),
      '{}'::text[]
    );
  end if;

  update public.executor_profiles
     set id_doc_path = coalesce(p_id_doc, id_doc_path),
         license_path = coalesce(p_license, license_path),
         tech_passport_path = coalesce(p_tech, tech_passport_path),
         tech_passport_selfie_path = coalesce(p_tech_selfie, tech_passport_selfie_path),
         id_selfie_path = coalesce(p_id_selfie, id_selfie_path),
         license_selfie_path = coalesce(p_license_selfie, license_selfie_path),
         passport_path = coalesce(p_passport, passport_path),
         passport_selfie_path = coalesce(p_passport_selfie, passport_selfie_path),
         vehicle_photos = coalesce(p_photos, vehicle_photos),
         docs_review_pending = true
   where user_id = auth.uid();

  return v_old;
end;
$$;

grant execute on function public.submit_docs_update(
  text,text,text,text[],text,text,text,text,text) to authenticated;
