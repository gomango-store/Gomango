// ============================================================
// 계정관리(바이저 전용) API - Supabase Edge Function
// 계정 생성/수정/삭제는 service_role 권한이 필요해서 브라우저에서 바로 할 수 없기 때문에,
// 이 함수가 대신 처리합니다. 호출자가 실제로 "바이저" role인지 매번 서버에서 확인합니다.
//
// 배포 방법 (README.md 참고):
//   supabase functions deploy admin-users
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY는 Supabase가 Edge Function 실행 환경에
// 자동으로 넣어주는 값이라 따로 설정할 필요가 없습니다.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "").trim();
    if (!token) return json({ error: "인증 토큰이 없습니다." }, 401);

    // service_role 권한 클라이언트 (관리자 API 전용, RLS 우회)
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 호출한 사람이 누구인지 토큰으로 확인
    const { data: userData, error: userErr } = await admin.auth.getUser(token);
    if (userErr || !userData?.user) return json({ error: "인증에 실패했습니다." }, 401);
    const callerId = userData.user.id;

    // 호출한 사람이 바이저인지 확인 (바이저가 아니면 어떤 동작도 허용하지 않습니다)
    const { data: callerProfile, error: callerErr } = await admin
      .from("profiles")
      .select("role")
      .eq("id", callerId)
      .maybeSingle();

    if (callerErr) {
      console.error("caller profile 조회 실패:", callerErr.message, "callerId:", callerId);
      return json({ error: "권한 확인 중 오류가 발생했습니다: " + callerErr.message }, 500);
    }
    if (!callerProfile) {
      console.error("caller profile 행이 없습니다. callerId:", callerId);
      return json({ error: `계정 정보(profiles)를 찾을 수 없습니다. (id: ${callerId})` }, 403);
    }
    if (callerProfile.role !== "visor") {
      console.error("바이저가 아닌 계정의 호출. callerId:", callerId, "role:", callerProfile.role);
      return json({ error: `바이저 권한이 필요합니다. (현재 권한: ${callerProfile.role})` }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const action = body.action;

    // ---------- 목록 조회 ----------
    if (action === "list") {
      const { data: profiles, error: pErr } = await admin
        .from("profiles")
        .select("*")
        .order("created_at", { ascending: true });
      if (pErr) return json({ error: pErr.message }, 400);

      const { data: usersPage, error: uErr } = await admin.auth.admin.listUsers({ perPage: 1000 });
      if (uErr) return json({ error: uErr.message }, 400);

      const emailMap: Record<string, string> = {};
      (usersPage?.users || []).forEach((u: any) => {
        emailMap[u.id] = u.email || "";
      });

      const accounts = (profiles || []).map((p: any) => ({ ...p, email: emailMap[p.id] || "" }));
      return json({ accounts });
    }

    // ---------- 계정 생성 ----------
    if (action === "create") {
      const { email, password, store_name, role } = body;
      if (!email || !password || !store_name || !role) {
        return json({ error: "필수 항목이 누락되었습니다." }, 400);
      }
      if (!["owner", "visor"].includes(role)) {
        return json({ error: "권한 값이 올바르지 않습니다." }, 400);
      }
      if (String(password).length < 6) {
        return json({ error: "비밀번호는 6자 이상이어야 합니다." }, 400);
      }

      const { data: created, error: cErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { store_name, role },
      });
      if (cErr) return json({ error: cErr.message }, 400);

      // DB 트리거(on_auth_user_created)가 profiles 행을 자동으로 만들어주지만,
      // 혹시 메타데이터가 누락되는 경우를 대비해 한 번 더 확실하게 맞춰줍니다.
      const { error: upsertErr } = await admin
        .from("profiles")
        .upsert({ id: created.user.id, store_name, role });
      if (upsertErr) return json({ error: upsertErr.message }, 400);

      return json({ ok: true });
    }

    // ---------- 계정 수정 (매장명/권한/비밀번호) ----------
    if (action === "update") {
      const { id, store_name, role, password } = body;
      if (!id) return json({ error: "대상 계정이 없습니다." }, 400);
      if (role && !["owner", "visor"].includes(role)) {
        return json({ error: "권한 값이 올바르지 않습니다." }, 400);
      }
      if (password) {
        if (String(password).length < 6) {
          return json({ error: "비밀번호는 6자 이상이어야 합니다." }, 400);
        }
        const { error: pwErr } = await admin.auth.admin.updateUserById(id, { password });
        if (pwErr) return json({ error: pwErr.message }, 400);
      }
      const { error: upErr } = await admin
        .from("profiles")
        .update({ store_name, role })
        .eq("id", id);
      if (upErr) return json({ error: upErr.message }, 400);

      return json({ ok: true });
    }

    // ---------- 계정 삭제 ----------
    if (action === "delete") {
      const { id } = body;
      if (!id) return json({ error: "대상 계정이 없습니다." }, 400);
      if (id === callerId) return json({ error: "본인 계정은 삭제할 수 없습니다." }, 400);

      const { error: delErr } = await admin.auth.admin.deleteUser(id);
      if (delErr) return json({ error: delErr.message }, 400);

      return json({ ok: true });
    }

    return json({ error: "알 수 없는 요청입니다." }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
