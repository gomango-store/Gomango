-- ============================================================
-- JUICY 파트너 게시판 - 게시글 수정/삭제 기능 추가 마이그레이션
-- 이미 sql/schema.sql을 한 번 실행해서 DB가 구축되어 있는 상태라면,
-- 전체를 다시 실행할 필요 없이 이 파일만 SQL Editor에 붙여넣고 실행하면 됩니다.
-- (schema.sql의 11번 섹션과 내용이 동일하며, 여러 번 실행해도 안전합니다)
-- ============================================================

-- 수정일시(updated_at) 컬럼 추가 (이미 있으면 건너뜀)
alter table public.notices add column if not exists updated_at timestamptz not null default now();
alter table public.recipes add column if not exists updated_at timestamptz not null default now();
alter table public.resources add column if not exists updated_at timestamptz not null default now();
alter table public.companies add column if not exists updated_at timestamptz not null default now();
alter table public.suggestions add column if not exists updated_at timestamptz not null default now();
alter table public.supply_requests add column if not exists updated_at timestamptz not null default now();

-- UPDATE 될 때마다 updated_at을 현재 시각으로 자동 갱신해주는 함수/트리거
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_updated_at on public.notices;
create trigger set_updated_at before update on public.notices for each row execute procedure public.set_updated_at();

drop trigger if exists set_updated_at on public.recipes;
create trigger set_updated_at before update on public.recipes for each row execute procedure public.set_updated_at();

drop trigger if exists set_updated_at on public.resources;
create trigger set_updated_at before update on public.resources for each row execute procedure public.set_updated_at();

drop trigger if exists set_updated_at on public.companies;
create trigger set_updated_at before update on public.companies for each row execute procedure public.set_updated_at();

drop trigger if exists set_updated_at on public.suggestions;
create trigger set_updated_at before update on public.suggestions for each row execute procedure public.set_updated_at();

drop trigger if exists set_updated_at on public.supply_requests;
create trigger set_updated_at before update on public.supply_requests for each row execute procedure public.set_updated_at();

-- 건의사항: 작성자 본인도 자신의 글을 "수정"할 수 있도록 허용 (삭제는 여전히 바이저만 가능)
drop policy if exists "suggestions_update_own" on public.suggestions;
create policy "suggestions_update_own" on public.suggestions
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists "suggestions_delete_visor" on public.suggestions;
create policy "suggestions_delete_visor" on public.suggestions
  for delete using (public.is_visor());

-- 본사 발주: 작성자 본인도 자신의 요청을 "수정"할 수 있도록 허용 (삭제는 여전히 바이저만 가능)
drop policy if exists "supply_requests_update_own" on public.supply_requests;
create policy "supply_requests_update_own" on public.supply_requests
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists "supply_requests_delete_visor" on public.supply_requests;
create policy "supply_requests_delete_visor" on public.supply_requests
  for delete using (public.is_visor());

-- 참고: 공지사항/레시피/자료실/업체정보는 원래 "..._write_visor" (for all) 정책이 있어서
-- 바이저의 수정·삭제 권한이 이미 포함되어 있습니다. 이 테이블들은 점주가 작성하지 않으므로
-- 별도의 "본인 수정" 정책이 필요 없습니다.
