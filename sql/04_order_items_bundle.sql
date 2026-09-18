-- ============================================================
-- GOMANGO 파트너 게시판 - 발주 요청 다중 물품 묶음 저장 마이그레이션
-- SQL Editor에 이 파일 내용을 붙여넣고 실행하세요. 여러 번 실행해도 안전합니다.
-- (한 번에 여러 물품을 "추가 요청"으로 신청해도 발주 목록에 한 건으로 묶여서 보이게 하기 위한 변경입니다)
-- ============================================================

-- 1) 여러 물품을 하나의 요청 건에 담을 수 있도록 items(jsonb 배열) 컬럼을 추가합니다.
--    예: [{"item_name": "배망 (2000EA/BOX)", "quantity": "2박스"}, {"item_name": "맨투맨", "quantity": "95 / 3개"}]
alter table public.supply_requests add column if not exists items jsonb;

-- 2) 기존에는 물품 1개만 저장했던 item_name/quantity 컬럼을 그대로 남겨두되(예전 데이터 호환),
--    새로 저장되는 요청은 items 배열만 채우고 item_name/quantity는 비워두므로 NOT NULL 제약을 풉니다.
alter table public.supply_requests alter column item_name drop not null;
