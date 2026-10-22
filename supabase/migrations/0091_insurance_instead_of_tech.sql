-- ============================================================
-- Tasu · 0091_insurance_instead_of_tech.sql
-- ============================================================
-- Кейбір орындаушыда көліктің техпаспорты жоқ, бірақ сол көлікке
-- страховка (полис) бар. Енді техпаспорттың орнына СТРАХОВКА + онымен
-- фото жүктеуге болады (екеуі бірдей міндетті емес — біреуі жеткілікті).
--
--   * executor_profiles.insurance_path / insurance_selfie_path
--   * submit_docs_update (модератор құжатты қайта сұрағанда) страховканы да
--     қабылдайды, ескі файлдарын Storage-тан тазалау үшін қайтарады.
--     Ескі қосымша нұсқалары жаңа параметрлерсіз де жұмыс істей береді.
--
-- Қосымша жаңа нұсқасы шықпай тұрып қолданыңыз. Идемпотентті.
-- Supabase SQL Editor-да не MCP арқылы қолданылады (0090-нан кейін).
-- ============================================================

alter table public.executor_profiles
  add column if not exists insurance_path text,
  add column if not exists insurance_selfie_path text;

comment on column public.executor_profiles.insurance_path is
  'Көлік страховкасы (техпаспорт жоқ болса, оның орнына) (0091)';
comment on column public.executor_profiles.insurance_selfie_path is
  'Страховкамен фото (0091)';

drop function if exists public.submit_docs_update(text,text,text,text[],text,text,text,text,text);
drop function if exists public.submit_docs_update(text,text,text,text[],text,text,text,text,text,text,text);

create function public.submit_docs_update(
  p_id_doc text default null,
  p_license text default null,
  p_tech text default null,
  p_photos text[] default null,
  p_id_selfie text default null,
  p_license_selfie text default null,
  p_passport text default null,
  p_passport_selfie text default null,
  p_tech_selfie text default null,
  p_insurance text default null,
  p_insurance_selfie text default null)
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
  -- ғана "ескі" деп есептеледі — тимегенін жоймаймыз.
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
  if p_insurance is not null and ep.insurance_path is not null
     and p_insurance <> ep.insurance_path then
    v_old := v_old || ep.insurance_path;
  end if;
  if p_insurance_selfie is not null and ep.insurance_selfie_path is not null
     and p_insurance_selfie <> ep.insurance_selfie_path then
    v_old := v_old || ep.insurance_selfie_path;
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
         insurance_path = coalesce(p_insurance, insurance_path),
         insurance_selfie_path = coalesce(p_insurance_selfie, insurance_selfie_path),
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
  text,text,text,text[],text,text,text,text,text,text,text) to authenticated;
