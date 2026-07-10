-- GazelGo · 0023_citizenship_tech_docs.sql
-- Азаматтыққа қарай жеке құжат (ҚР куәлігі / шетел паспорты) + міндетті
-- көлік техпаспорты + селфи. tech_passport_path кестеде бұрыннан бар
-- болатын, бірақ executor_apply_screen ешқашан жинамаған — енді толық
-- жіберіледі.

alter table public.executor_profiles
  add column if not exists tech_passport_selfie_path text;
alter table public.executor_profiles
  add column if not exists is_foreign_citizen boolean not null default false;

drop function if exists public.submit_docs_update(text,text,text,text[],text,text,text,text);
create or replace function public.submit_docs_update(
  p_id_doc text default null,
  p_license text default null,
  p_tech text default null,
  p_photos text[] default null,
  p_id_selfie text default null,
  p_license_selfie text default null,
  p_passport text default null,
  p_passport_selfie text default null,
  p_tech_selfie text default null)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  update public.executor_profiles
     set id_doc_path = coalesce(p_id_doc, id_doc_path),
         license_path = coalesce(p_license, license_path),
         tech_passport_path = coalesce(p_tech, tech_passport_path),
         tech_passport_selfie_path = coalesce(p_tech_selfie, tech_passport_selfie_path),
         id_selfie_path = coalesce(p_id_selfie, id_selfie_path),
         license_selfie_path = coalesce(p_license_selfie, license_selfie_path),
         passport_path = coalesce(p_passport, passport_path),
         passport_selfie_path = coalesce(p_passport_selfie, passport_selfie_path),
         docs_review_pending = true
   where user_id = auth.uid();
  if not found then raise exception 'NOT_EXECUTOR'; end if;
end;
$$;

grant execute on function public.submit_docs_update(
  text,text,text,text[],text,text,text,text,text) to authenticated;
