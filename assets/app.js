// ============================================================
// 공용 헬퍼: 로그인 체크, GNB 렌더링, 유틸 함수
// ============================================================

const GNB_ITEMS = [
  { key: "home", href: "home", label: "홈" },
  { key: "recipes", href: "recipes", label: "레시피" },
  { key: "notices", href: "notices", label: "공지사항" },
  { key: "suggestions", href: "suggestions", label: "건의함", visorOnly: true },
  { key: "faq", href: "faq", label: "FAQ" },
  { key: "orders", href: "orders", label: "본사 발주" },
  { key: "resources", href: "resources", label: "자료실" },
  { key: "company", href: "company", label: "업체 정보" },
  { key: "accounts", href: "accounts", label: "계정관리", visorOnly: true },
];

// 페이지는 기본적으로 style.css에 의해 숨겨져 있습니다 (html:not(.js-ready) body{visibility:hidden}).
// 로그인 확인이 끝나고 화면을 보여줘도 되는 시점에만 이 함수를 호출하세요.
function revealPage() {
  document.documentElement.classList.add("js-ready");
}

// 로그인 안 되어 있으면 login.html 로 즉시 이동시키고(화면이 보이지 않은 채로), 되어 있으면 { session, profile } 반환
async function requireAuth() {
  const { data: { session }, error } = await sb.auth.getSession();
  if (error || !session) {
    location.replace("login");
    return null;
  }
  const { data: profile, error: profileError } = await sb
    .from("profiles")
    .select("*")
    .eq("id", session.user.id)
    .single();

  if (profileError) {
    console.error("프로필 조회 실패:", profileError.message);
  }
  return { session, profile: profile || null };
}

function isVisor(profile) {
  return !!profile && profile.role === "visor";
}

// ============================================================
// 아이디 로그인 지원
// Supabase Auth는 이메일(또는 전화번호)로만 로그인할 수 있어서, 화면에서는 "아이디"만
// 입력받고 내부적으로 가짜 이메일 주소(아이디@juicy-board.local)로 변환해서 사용합니다.
// (실제 발송되지 않는 주소라, 이메일로 보내는 "비밀번호 찾기" 기능은 사용할 수 없고,
//  비밀번호 재설정은 계정관리 화면에서 바이저가 직접 눌러줘야 합니다.)
// "@"가 포함된 값을 입력하면(예: 예전에 실제 이메일로 만들어둔 계정) 변환하지 않고 그대로 씁니다.
// ============================================================
const ID_EMAIL_DOMAIN = "juicy-board.local";

function idToEmail(id) {
  const trimmed = String(id || "").trim();
  return trimmed.includes("@") ? trimmed : `${trimmed}@${ID_EMAIL_DOMAIN}`;
}

// 이메일에서 표시용 아이디만 꺼냅니다. 우리가 만든 가짜 도메인이면 아이디만 보여주고,
// (예전에 만들어둔) 실제 이메일이면 그 이메일을 그대로 보여줍니다.
function emailToId(email) {
  const value = String(email || "");
  const suffix = `@${ID_EMAIL_DOMAIN}`;
  return value.endsWith(suffix) ? value.slice(0, -suffix.length) : value;
}

// 아이디로 쓸 수 있는 문자만 허용합니다 (영문 소문자/숫자/. _ -), 가짜 이메일로 변환했을 때
// 유효한 이메일 형식이 되도록 하기 위함입니다.
function isValidLoginId(id) {
  return /^[a-z0-9._-]{2,40}$/i.test(String(id || "").trim());
}

// GNB를 #gnb 요소 안에 그려줍니다. (모바일에서는 햄버거 버튼으로 접이식 메뉴가 열립니다)
function renderGnb(activeKey, profile) {
  const gnbEl = document.getElementById("gnb");
  if (!gnbEl) return;

  const visibleItems = GNB_ITEMS.filter((item) => !item.visorOnly || isVisor(profile));
  const linksHtml = visibleItems.map(
    (item) => `
      <a href="${item.href}" class="gnb-link ${item.key === activeKey ? "active" : ""}">${item.label}</a>
    `
  ).join("");

  gnbEl.innerHTML = `
    <div class="gnb-inner">
      <div class="gnb-brand">
        <button id="gnbHamburger" class="gnb-hamburger" aria-label="메뉴 열기">
          <span></span><span></span><span></span>
        </button>
        <a href="home" style="text-decoration:none; display:flex; align-items:center;"><img src="assets/logo.png?v=20260918" alt="GOMANGO" class="brand-logo"></a>
        <span class="gnb-divider"></span>
        <span class="gnb-sub">점주 운영 게시판</span>
      </div>
      <nav class="gnb-nav">${linksHtml}</nav>
      <div class="gnb-right">
        <div class="store-chip">${escapeHtml(profile ? profile.store_name : "")}</div>
        <button id="logoutBtn" class="btn-link">로그아웃</button>
      </div>
    </div>
    <nav class="gnb-mobile-nav" id="gnbMobileNav">${linksHtml}</nav>
    <div class="gnb-mobile-backdrop" id="gnbMobileBackdrop"></div>
  `;

  document.getElementById("logoutBtn").addEventListener("click", async () => {
    await sb.auth.signOut();
    location.href = "login";
  });

  const hamburger = document.getElementById("gnbHamburger");
  const mobileNav = document.getElementById("gnbMobileNav");
  const backdrop = document.getElementById("gnbMobileBackdrop");
  function closeMobileNav() {
    mobileNav.classList.remove("open");
    backdrop.classList.remove("open");
    hamburger.classList.remove("open");
  }
  function toggleMobileNav() {
    mobileNav.classList.toggle("open");
    backdrop.classList.toggle("open");
    hamburger.classList.toggle("open");
  }
  hamburger.addEventListener("click", toggleMobileNav);
  backdrop.addEventListener("click", closeMobileNav);
  mobileNav.querySelectorAll("a").forEach((a) => a.addEventListener("click", closeMobileNav));
}

function escapeHtml(str) {
  if (str === null || str === undefined) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatDate(isoString) {
  if (!isoString) return "";
  const d = new Date(isoString);
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${mm}.${dd}`;
}

// 날짜 + 시간까지 함께 표시합니다 (예: 09.17 14:32)
function formatDateTime(isoString) {
  if (!isoString) return "";
  const d = new Date(isoString);
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  const hh = String(d.getHours()).padStart(2, "0");
  const mi = String(d.getMinutes()).padStart(2, "0");
  return `${mm}.${dd} ${hh}:${mi}`;
}

// 작성 후 수정된 적이 있는지 여부 (updated_at이 created_at과 다르면 수정된 것으로 간주)
function isEdited(row) {
  if (!row || !row.updated_at || !row.created_at) return false;
  return new Date(row.updated_at).getTime() !== new Date(row.created_at).getTime();
}

// 작성/수정 일시를 함께 표시하는 공용 문구 (수정된 경우 "(수정됨)" 문구 포함)
function metaDateLabel(row) {
  if (!row) return "";
  if (isEdited(row)) {
    return `${formatDateTime(row.updated_at)} <span class="edited-tag">(수정됨)</span>`;
  }
  return formatDateTime(row.created_at);
}

function isWithinDays(isoString, days) {
  if (!isoString) return false;
  const then = new Date(isoString).getTime();
  const now = Date.now();
  return now - then <= days * 24 * 60 * 60 * 1000;
}

// 문자열을 n자까지만 보여주고 넘으면 ...으로 말줄임 처리합니다.
function truncate(str, n) {
  if (!str) return "";
  const s = String(str);
  return s.length > n ? s.slice(0, n) + "…" : s;
}

// 유튜브 링크(watch, youtu.be, shorts, embed 등 다양한 형태)에서 영상 ID를 추출합니다.
function getYoutubeId(url) {
  if (!url) return null;
  try {
    const u = new URL(url);
    const host = u.hostname.replace(/^www\./, "");
    if (host === "youtu.be") {
      return u.pathname.slice(1).split("/")[0] || null;
    }
    if (host === "youtube.com" || host === "m.youtube.com" || host === "music.youtube.com") {
      if (u.searchParams.get("v")) return u.searchParams.get("v");
      const parts = u.pathname.split("/").filter(Boolean); // ["shorts", "ID"] or ["embed", "ID"]
      if ((parts[0] === "shorts" || parts[0] === "embed" || parts[0] === "live") && parts[1]) {
        return parts[1];
      }
    }
  } catch (e) {
    return null;
  }
  return null;
}

// 유튜브 링크면 썸네일 이미지 URL을, 아니면 null을 반환합니다.
function getYoutubeThumbUrl(url) {
  const id = getYoutubeId(url);
  return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : null;
}

// 구글 드라이브 공유 링크(file/d/... 또는 open?id=... 형태)에서 파일 ID를 추출합니다.
// (공지사항 이미지 첨부에 사용 — 파일 공유 설정이 "링크가 있는 모든 사용자"로 되어 있어야 썸네일이 보입니다)
function getGoogleDriveId(url) {
  if (!url) return null;
  try {
    const u = new URL(url);
    const host = u.hostname.replace(/^www\./, "");
    if (host !== "drive.google.com" && host !== "docs.google.com") return null;
    const fileMatch = u.pathname.match(/\/file\/d\/([a-zA-Z0-9_-]+)/);
    if (fileMatch) return fileMatch[1];
    if (u.searchParams.get("id")) return u.searchParams.get("id");
  } catch (e) {
    return null;
  }
  return null;
}

// 구글 드라이브 링크면 썸네일 이미지 URL을, 아니면 null을 반환합니다.
function getGoogleDriveThumbUrl(url) {
  const id = getGoogleDriveId(url);
  return id ? `https://drive.google.com/thumbnail?id=${id}&sz=w1000` : null;
}

// 구글 드라이브 링크면 보기/다운로드 화면으로 이동하는 표준 링크를, 아니면 원래 입력값을 그대로 반환합니다.
function getGoogleDriveViewUrl(url) {
  const id = getGoogleDriveId(url);
  return id ? `https://drive.google.com/file/d/${id}/view` : url;
}

// 전화번호 문자열에서 하이픈/공백을 제거해 tel: 링크에 쓸 수 있게 만듭니다.
function toTelHref(phone) {
  if (!phone) return "";
  return "tel:" + String(phone).replace(/[^0-9+]/g, "");
}

// 분류(카테고리) 문자열마다 색상을 다르게 보여주기 위한 pill 클래스 매핑.
// 목록에 없는 카테고리는 기본(pill-neutral)로 표시됩니다.
// (pill-accent는 브랜드 노란색이라 흰 배경 위에서는 색이 잘 안 보여서 분류 태그에는 쓰지 않았습니다)
const CATEGORY_PILL_MAP = {
  // 자료실
  "매뉴얼": "pill-info",
  "서식": "pill-secondary",
  "포스터": "pill-amber",
  // 업체 정보
  "재료": "pill-secondary",
  "장비/AS": "pill-info",
  "포장재": "pill-amber",
};

function categoryPillClass(category) {
  return CATEGORY_PILL_MAP[category] || "pill-neutral";
}

// 건의함 구분(문의사항/건의사항/메뉴 의견)별 색상
const SUGGESTION_CATEGORY_PILL_MAP = {
  "업무": "pill-amber",
  "메모": "pill-secondary",
  "문의사항": "pill-info",
  "건의사항": "pill-amber",
  "메뉴 의견": "pill-secondary",
};
function suggestionCategoryPillClass(category) {
  return SUGGESTION_CATEGORY_PILL_MAP[category] || "pill-neutral";
}

// 금액을 "12,000원" 형태로 표시합니다.
function formatWon(n) {
  const num = Number(n) || 0;
  return num.toLocaleString("ko-KR") + "원";
}

// 숫자를 "12,000" 형태(천단위 콤마, "원" 접미사 없음)로 표시합니다. 입력용 필드에 사용합니다.
function formatNumber(n) {
  const num = Number(n) || 0;
  return num.toLocaleString("ko-KR");
}

// "12,000" 같은 콤마 포함 문자열을 숫자로 되돌립니다.
function parseNumber(str) {
  if (str === null || str === undefined) return 0;
  const cleaned = String(str).replace(/[^0-9.-]/g, "");
  return Number(cleaned) || 0;
}

// 발주 수량/단위 문자열(예: "3박스", "2팩", "95", "95 / 3개")에서 곱해줄 개수를 뽑아냅니다.
// "N박스"/"N팩"/"N개" 부분이 어디에 있든 그 숫자를 쓰고, 없으면(사이즈만 있는 경우 등) 1을 반환합니다.
function parseOrderQtyMultiplier(optionStr) {
  if (!optionStr) return 1;
  const m = String(optionStr).match(/(\d+)\s*(박스|팩|개)/);
  return m ? parseInt(m[1], 10) : 1;
}

function showFormError(el, message) {
  el.textContent = message;
  el.classList.remove("hidden");
}

function clearFormError(el) {
  el.textContent = "";
  el.classList.add("hidden");
}
