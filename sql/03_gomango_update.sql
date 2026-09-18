-- ============================================================
-- GOMANGO 파트너 게시판 - 건의함 구분 / 발주 물품 가격·송금상태 추가 마이그레이션
-- SQL Editor에 이 파일 내용을 붙여넣고 실행하세요. 여러 번 실행해도 안전합니다.
-- (sql/02_edit_delete_migration.sql을 아직 실행하지 않았어도 이 파일 하나만 실행하면 됩니다)
-- ============================================================

-- UPDATE 될 때마다 updated_at을 자동 갱신해주는 함수 (02번 마이그레이션과 동일, 안전하게 재선언)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- 1) 건의함: 구분(문의사항/건의사항/메뉴 의견) 컬럼 추가
alter table public.suggestions add column if not exists category text not null default '건의사항';
alter table public.suggestions drop constraint if exists suggestions_category_check;
alter table public.suggestions add constraint suggestions_category_check check (category in ('문의사항', '건의사항', '메뉴 의견'));

-- 2) 본사 발주: 송금 상태 컬럼 추가 (기본값 "미완료")
alter table public.supply_requests add column if not exists payment_status text not null default '미완료';
alter table public.supply_requests drop constraint if exists supply_requests_payment_status_check;
alter table public.supply_requests add constraint supply_requests_payment_status_check check (payment_status in ('미완료', '완료'));

-- 3) 발주 품목별 단가 테이블
-- 로그인한 사람은 누구나 조회할 수 있고(예상 금액 계산용), 작성/수정/삭제는 바이저만 가능합니다.
create table if not exists public.order_item_prices (
  item_name text primary key,
  unit_price numeric not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.order_item_prices enable row level security;

drop policy if exists "order_item_prices_select_authenticated" on public.order_item_prices;
create policy "order_item_prices_select_authenticated" on public.order_item_prices
  for select using (auth.role() = 'authenticated');

drop policy if exists "order_item_prices_write_visor" on public.order_item_prices;
create policy "order_item_prices_write_visor" on public.order_item_prices
  for all using (public.is_visor()) with check (public.is_visor());

drop trigger if exists set_updated_at on public.order_item_prices;
create trigger set_updated_at before update on public.order_item_prices for each row execute procedure public.set_updated_at();

grant select, insert, update, delete on public.order_item_prices to authenticated;

-- 발주 가능 품목 7종의 가격 행을 기본 단가 0원으로 미리 만들어둡니다.
-- (바이저가 orders.html의 "발주 금액 설정" 화면에서 실제 단가로 수정하면 됩니다)
insert into public.order_item_prices (item_name, unit_price) values
  ('배망 (2000EA/BOX)', 0),
  ('반팔티셔츠', 0),
  ('앞치마 (검정/FREE)', 0),
  ('스냅백 (노랑/FREE)', 0),
  ('맨투맨', 0),
  ('무지 1구 비닐캐리어 (200EA/PK)', 0),
  ('무지 2구 비닐캐리어 (200EA/PK)', 0)
on conflict (item_name) do nothing;
