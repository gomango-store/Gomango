-- ============================================================
-- 계정관리(accounts.html) 기능에 필요한 마이그레이션
-- SQL Editor에 이 파일 내용을 붙여넣고 실행하세요. 여러 번 실행해도 안전합니다.
--
-- 계정 생성/수정/삭제를 대신 처리하는 Edge Function(admin-users)은
-- service_role 권한으로 DB에 접속합니다. service_role은 RLS(행 단위 보안 정책)는
-- 자동으로 우회하지만, "이 role이 이 테이블을 건드려도 되는가"라는 테이블 자체의
-- 접근 권한(GRANT)은 RLS와 별개로 반드시 따로 부여해야 합니다.
-- 지금까지는 anon/authenticated에게만 GRANT를 해뒀어서, service_role로 profiles
-- 테이블을 조회하면 "permission denied for table profiles" 오류가 발생했습니다.
-- 아래 GRANT문으로 service_role에도 접근 권한을 부여합니다.
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
