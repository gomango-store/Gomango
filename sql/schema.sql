-- ============================================================
-- GOMANGO 파트너 게시판 - Supabase 스키마
-- Supabase 대시보드 > SQL Editor 에 전체를 붙여넣고 실행하세요.
-- 이미 한 번 실행한 적이 있는 DB에 다시 실행해도 안전합니다(정책/트리거를 먼저
-- 지우고 다시 만드는 방식이라, "already exists" 오류 없이 재실행할 수 있습니다).
-- ============================================================

-- 1) 점주/바이저 프로필 테이블
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  store_name text not null default '미지정 매장',
  role text not null default 'owner' check (role in ('owner', 'visor')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- 역할 확인용 헬퍼 함수 (RLS 정책에서 재귀 없이 안전하게 사용하기 위해 security definer로 선언)
create or replace function public.is_visor()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'visor'
  );
$$;

drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles
  for select using (auth.uid() = id or public.is_visor());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- 회원가입(Auth 계정 생성) 시 profiles 행을 자동 생성해주는 트리거
-- Supabase 대시보드에서 계정을 만들 때 "User Metadata"에 store_name, role을 넣어두면 자동 반영됩니다.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, store_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'store_name', '미지정 매장'),
    coalesce(new.raw_user_meta_data->>'role', 'owner')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- 2) 공지사항
create table if not exists public.notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  content text not null,
  category text not null default '일반',
  is_pinned boolean not null default false,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.notices enable row level security;

drop policy if exists "notices_select_authenticated" on public.notices;
create policy "notices_select_authenticated" on public.notices
  for select using (auth.role() = 'authenticated');

drop policy if exists "notices_write_visor" on public.notices;
create policy "notices_write_visor" on public.notices
  for all using (public.is_visor()) with check (public.is_visor());


-- 3) 신메뉴/기존 메뉴 레시피
create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default '베이직 메뉴',
  video_url text,
  ingredients text[] not null default '{}',
  steps text[] not null default '{}',
  pdf_url text,
  is_new boolean not null default true,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.recipes enable row level security;

drop policy if exists "recipes_select_authenticated" on public.recipes;
create policy "recipes_select_authenticated" on public.recipes
  for select using (auth.role() = 'authenticated');

drop policy if exists "recipes_write_visor" on public.recipes;
create policy "recipes_write_visor" on public.recipes
  for all using (public.is_visor()) with check (public.is_visor());


-- 4) 자주 묻는 질문 (FAQ)
create table if not exists public.faqs (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  answer text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.faqs enable row level security;

drop policy if exists "faqs_select_authenticated" on public.faqs;
create policy "faqs_select_authenticated" on public.faqs
  for select using (auth.role() = 'authenticated');

drop policy if exists "faqs_write_visor" on public.faqs;
create policy "faqs_write_visor" on public.faqs
  for all using (public.is_visor()) with check (public.is_visor());


-- 5) 건의사항
create table if not exists public.suggestions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  content text not null,
  is_anonymous boolean not null default false,
  owner_id uuid not null references public.profiles(id),
  status text not null default '답변대기' check (status in ('답변대기', '답변완료')),
  created_at timestamptz not null default now()
);

alter table public.suggestions enable row level security;

-- 본인 글이거나, 바이저는 전체 조회 가능
drop policy if exists "suggestions_select" on public.suggestions;
create policy "suggestions_select" on public.suggestions
  for select using (owner_id = auth.uid() or public.is_visor());

-- 로그인한 점주 본인 명의로만 작성 가능
drop policy if exists "suggestions_insert" on public.suggestions;
create policy "suggestions_insert" on public.suggestions
  for insert with check (owner_id = auth.uid());

-- 상태 변경(답변완료 처리)은 바이저만
drop policy if exists "suggestions_update_visor" on public.suggestions;
create policy "suggestions_update_visor" on public.suggestions
  for update using (public.is_visor());


-- 6) 건의사항 답변
create table if not exists public.suggestion_replies (
  id uuid primary key default gen_random_uuid(),
  suggestion_id uuid not null references public.suggestions(id) on delete cascade,
  content text not null,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.suggestion_replies enable row level security;

drop policy if exists "replies_select" on public.suggestion_replies;
create policy "replies_select" on public.suggestion_replies
  for select using (
    exists (
      select 1 from public.suggestions s
      where s.id = suggestion_id and (s.owner_id = auth.uid() or public.is_visor())
    )
  );

drop policy if exists "replies_insert_visor" on public.suggestion_replies;
create policy "replies_insert_visor" on public.suggestion_replies
  for insert with check (public.is_visor());


-- 7) 자료실
create table if not exists public.resources (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default '문서',
  url text not null,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.resources enable row level security;

drop policy if exists "resources_select_authenticated" on public.resources;
create policy "resources_select_authenticated" on public.resources
  for select using (auth.role() = 'authenticated');

drop policy if exists "resources_write_visor" on public.resources;
create policy "resources_write_visor" on public.resources
  for all using (public.is_visor()) with check (public.is_visor());


-- 8) 업체 정보 (재료/장비 공급업체, AS 등 연락처 모음)
create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default '기타',
  contact_name text,
  phone text,
  email text,
  notes text,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.companies enable row level security;

drop policy if exists "companies_select_authenticated" on public.companies;
create policy "companies_select_authenticated" on public.companies
  for select using (auth.role() = 'authenticated');

drop policy if exists "companies_write_visor" on public.companies;
create policy "companies_write_visor" on public.companies
  for all using (public.is_visor()) with check (public.is_visor());


-- 9) 본사 발주 요청 (점주가 필요한 물품을 요청하고, 바이저가 발주 확인/댓글을 남깁니다)
create table if not exists public.supply_requests (
  id uuid primary key default gen_random_uuid(),
  item_name text not null,
  quantity text,
  note text,
  owner_id uuid not null references public.profiles(id),
  status text not null default '요청' check (status in ('요청', '발주완료')),
  created_at timestamptz not null default now()
);

alter table public.supply_requests enable row level security;

-- 건의사항과 동일한 원칙: 본인 글이거나 바이저는 전체 조회
drop policy if exists "supply_requests_select" on public.supply_requests;
create policy "supply_requests_select" on public.supply_requests
  for select using (owner_id = auth.uid() or public.is_visor());

drop policy if exists "supply_requests_insert" on public.supply_requests;
create policy "supply_requests_insert" on public.supply_requests
  for insert with check (owner_id = auth.uid());

drop policy if exists "supply_requests_update_visor" on public.supply_requests;
create policy "supply_requests_update_visor" on public.supply_requests
  for update using (public.is_visor());

create table if not exists public.supply_request_comments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.supply_requests(id) on delete cascade,
  content text not null,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.supply_request_comments enable row level security;

drop policy if exists "supply_request_comments_select" on public.supply_request_comments;
create policy "supply_request_comments_select" on public.supply_request_comments
  for select using (
    exists (
      select 1 from public.supply_requests r
      where r.id = request_id and (r.owner_id = auth.uid() or public.is_visor())
    )
  );

drop policy if exists "supply_request_comments_insert_visor" on public.supply_request_comments;
create policy "supply_request_comments_insert_visor" on public.supply_request_comments
  for insert with check (public.is_visor());


-- ============================================================
-- 10) 테이블 기본 권한 부여 (중요)
-- RLS 정책은 "어떤 행(row)을 볼 수 있는가"만 통제합니다. 그 이전에 로그인한 사용자
-- (authenticated 역할)가 테이블 자체를 건드릴 수 있는 기본 권한이 있어야 하므로,
-- 아래 GRANT 문을 반드시 함께 실행해야 합니다. (실수로 빠뜨리면
-- "permission denied for table ..." 오류가 발생합니다.)
-- ============================================================
grant usage on schema public to anon, authenticated;

grant select, insert, update, delete on
  public.profiles,
  public.notices,
  public.recipes,
  public.faqs,
  public.suggestions,
  public.suggestion_replies,
  public.resources,
  public.companies,
  public.supply_requests,
  public.supply_request_comments
to authenticated;


-- ============================================================
-- 11) 게시글 수정/삭제 지원 (수정일시 컬럼 + 자동 갱신 트리거 + 추가 권한 정책)
-- 이미 예전 버전의 schema.sql을 실행해서 DB가 구축되어 있다면, 이 11번 블록만
-- SQL Editor에서 새로 실행해도 동일하게 적용됩니다 (sql/02_edit_delete_migration.sql 참고).
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


-- ============================================================
-- 12) 건의함 구분 / 발주 물품 가격·송금상태 (sql/03_gomango_update.sql과 내용 동일)
-- ============================================================

-- 건의함: 구분(문의사항/건의사항/메뉴 의견) 컬럼 추가
alter table public.suggestions add column if not exists category text not null default '건의사항';
alter table public.suggestions drop constraint if exists suggestions_category_check;
alter table public.suggestions add constraint suggestions_category_check check (category in ('문의사항', '건의사항', '메뉴 의견'));

-- 본사 발주: 송금 상태 컬럼 추가 (기본값 "미완료")
alter table public.supply_requests add column if not exists payment_status text not null default '미완료';
alter table public.supply_requests drop constraint if exists supply_requests_payment_status_check;
alter table public.supply_requests add constraint supply_requests_payment_status_check check (payment_status in ('미완료', '완료'));

-- 발주 품목별 단가 테이블 (로그인한 사람 누구나 조회, 작성/수정/삭제는 바이저만)
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

insert into public.order_item_prices (item_name, unit_price) values
  ('배망 (2000EA/BOX)', 0),
  ('반팔티셔츠', 0),
  ('앞치마 (검정/FREE)', 0),
  ('스냅백 (노랑/FREE)', 0),
  ('맨투맨', 0),
  ('무지 1구 비닐캐리어 (200EA/PK)', 0),
  ('무지 2구 비닐캐리어 (200EA/PK)', 0)
on conflict (item_name) do nothing;


-- ============================================================
-- 13) 본사 발주: 여러 물품을 한 번에 요청해도 발주 목록에 한 건으로 묶어서 보이도록
--     items(jsonb 배열) 컬럼을 추가합니다. item_name은 예전 방식(단일 물품) 데이터 호환을
--     위해 남겨두되, 더 이상 필수 입력이 아니므로 NOT NULL 제약을 해제합니다.
-- ============================================================
alter table public.supply_requests add column if not exists items jsonb;
alter table public.supply_requests alter column item_name drop not null;


-- ============================================================
-- 14) 계정관리(accounts.html) 기능: 계정 생성/수정/삭제를 대신 처리하는
--     Edge Function(admin-users)이 service_role 권한으로 profiles 등 테이블에
--     접근할 수 있도록 GRANT를 부여합니다. (sql/05_service_role_grant.sql과 동일)
--     service_role은 RLS는 자동으로 우회하지만, 테이블 자체의 GRANT 권한은
--     RLS와 별개로 필요합니다 (없으면 "permission denied for table ..." 오류).
-- ============================================================
grant usage on schema public to service_role;

grant select, insert, update, delete on
  public.profiles,
  public.notices,
  public.recipes,
  public.faqs,
  public.suggestions,
  public.suggestion_replies,
  public.resources,
  public.companies,
  public.supply_requests,
  public.supply_request_comments,
  public.order_item_prices
to service_role;


-- ============================================================
-- 15) 공지사항 이미지 첨부(구글 드라이브 링크) 기능 (sql/06_notices_image.sql과 동일)
-- ============================================================
alter table public.notices add column if not exists image_url text;


-- ============================================================
-- (선택) 화면 미리보기용 샘플 데이터 - 필요 없으면 지우고 실행하세요.
-- 아래 INSERT는 author_id/owner_id를 비워두면 실패하니, 먼저 계정을 만든 뒤
-- 해당 계정의 uuid로 author_id 값을 바꿔서 실행해도 됩니다. 그냥 건너뛰어도 무방합니다.
-- ============================================================
-- insert into public.faqs (question, answer, sort_order) values
--   ('포장 용기·빨대는 어디서 추가 주문하나요?', '자료실 > 발주 서식에서 포장재 발주서를 다운로드해 물류팀 이메일로 보내주세요.', 1),
--   ('직원 급여 정산일이 언제인가요?', '매월 10일 마감 후 15일에 지급됩니다.', 2);
