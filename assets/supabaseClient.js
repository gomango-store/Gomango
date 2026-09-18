// ============================================================
// Supabase 연결 설정
// 1) Supabase 대시보드 > Project Settings > API 에서 아래 두 값을 복사해서 넣어주세요.
// 2) 이 파일은 브라우저에 그대로 노출됩니다. anon key는 공개되어도 되는 키이지만
//    (RLS 정책이 실제 접근 권한을 통제합니다), service_role 키는 절대 여기에 넣지 마세요.
// ============================================================
const SUPABASE_URL = "https://YOUR-PROJECT-REF.supabase.co"; // TODO: 본인 프로젝트 URL로 변경
const SUPABASE_ANON_KEY = "YOUR-ANON-PUBLIC-KEY"; // TODO: 본인 anon public key로 변경

// window.supabase 는 CDN으로 불러온 supabase-js 라이브러리 전역 객체입니다.
// 우리 클라이언트 인스턴스는 이름 충돌을 피하기 위해 sb 라는 이름으로 둡니다.
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
