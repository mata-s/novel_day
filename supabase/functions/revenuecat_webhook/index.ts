// supabase/functions/revenuecat_webhook/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// service_role で DB 更新用クライアント
const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

// RevenueCat 側に設定するシークレット（任意だけど本当はやった方が良い）
const RC_WEBHOOK_SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // ─────────────────────────────
  // (オプション) シンプルな署名チェック
  // ─────────────────────────────
  if (RC_WEBHOOK_SECRET) {
    const authHeader = req.headers.get("authorization") ?? "";
    console.log("authHeader:", authHeader);
    console.log("expected:", `Bearer ${RC_WEBHOOK_SECRET}`);
    if (authHeader !== `Bearer ${RC_WEBHOOK_SECRET}`) {
      console.error("Invalid webhook secret");
      return new Response("Unauthorized", { status: 401 });
    }
  }

  let body: any;
  try {
    body = await req.json();
  } catch (e) {
    console.error("Failed to parse JSON:", e);
    return new Response("Bad Request", { status: 400 });
  }

  // RevenueCat Webhook の型は v1/v2 で微妙に違うので両方に少し対応
  console.log("RevenueCat raw payload:", body);

  // 1. app_user_id / appUserId を柔軟に取得
  let appUserIdRaw: string | null =
    body.app_user_id ??
    body.appUserId ??
    body.event?.app_user_id ??
    body.event?.appUserId ??
    body.subscriber?.app_user_id ??
    body.subscriber?.appUserId ??
    null;

  // TRANSFER イベントの場合は transferred_to から appUserId を解決
  if (!appUserIdRaw && body.event?.type === "TRANSFER") {
    const transferredTo = body.event?.transferred_to as string[] | undefined;
    if (Array.isArray(transferredTo)) {
      // $RCAnonymousID: ではじまらない ID を優先的に使う
      const resolved = transferredTo.find((id) =>
        typeof id === "string" && !id.startsWith("$RCAnonymousID:")
      );
      if (resolved) {
        appUserIdRaw = resolved;
        console.log("Resolved appUserId from transferred_to:", appUserIdRaw);
      }
    }
  }

  if (!appUserIdRaw || typeof appUserIdRaw !== "string") {
    console.error("app_user_id / appUserId not found in payload");
    return new Response("OK", { status: 200 }); // ここは 200 返しておく（リトライされまくるの防止）
  }

  // 匿名ユーザー ($RCAnonymousID:...) のイベントは無視する
  if (appUserIdRaw.startsWith("$RCAnonymousID:")) {
    console.log("Ignore anonymous RevenueCat event for appUserId:", appUserIdRaw);
    return new Response("OK", { status: 200 });
  }

  const appUserId = appUserIdRaw;
  console.log("Resolved appUserId:", appUserId);

  // 2. サブスクが有効かどうかを判定
  //    - entitlements の is_active
  //    - なければ event.type から推定
  const entitlementsObj =
    body.entitlements ??
    body.event?.entitlements ??
    body.subscriber?.entitlements ??
    null;
  console.log("RevenueCat entitlements raw:", entitlementsObj);

  let isActive: boolean | null = null;

  if (entitlementsObj && typeof entitlementsObj === "object") {
    const values = Object.values(entitlementsObj as Record<string, any>);
    console.log(
      "RevenueCat entitlements values:",
      JSON.stringify(values, null, 2),
    );
    if (values.length > 0) {
      // どれか 1 つでも is_active === true なら有効とみなす
      isActive = values.some((ent: any) => ent && ent.is_active === true);
    }
  }

  // entitlements で判定できなかった場合のフォールバック
  const eventType = body.type ?? body.event?.type ?? "unknown";
  if (isActive === null) {
    const activeTypes = new Set([
      "INITIAL_PURCHASE",
      "RENEWAL",
      "PRODUCT_CHANGE",
      "UNCANCELLATION",
      "BILLING_RECOVERY",
      "TRANSFER",
    ]);
    const inactiveTypes = new Set([
      "CANCELLATION",
      "EXPIRATION",
      "BILLING_ISSUE",
    ]);

    if (activeTypes.has(eventType)) {
      isActive = true;
    } else if (inactiveTypes.has(eventType)) {
      isActive = false;
    } else {
      // ここまで来たら一旦 false 扱いにしておく
      isActive = false;
    }
  }

  console.log(
    "RevenueCat webhook decision:",
    JSON.stringify(
      {
        appUserId,
        eventType,
        entitlementsObj,
        isActive,
      },
      null,
      2,
    ),
  );

  // ─────────────────────────────
  // ここで profiles.is_premium を更新
  // ─────────────────────────────
  //
  // ★ 重要 ★
  // appUserId と profiles の紐付け方法のパターン:
  //  ① Novel Day で「Supabaseの user.id を RevenueCatの appUserId にしている」なら:
  //     → profiles.id = appUserId で OK
  //  ② BackupID を appUserId にしているなら:
  //     → profiles.backup_id = appUserId みたいに書き換える
  //
  // ここでは ① のパターンで書いておくね。

  console.log(
    "Updating profiles.is_premium",
    JSON.stringify(
      {
        appUserId,
        isActive,
      },
      null,
      2,
    ),
  );
  const { error } = await supabase
    .from("profiles")
    .update({ is_premium: isActive })
    .eq("id", appUserId);

  if (error) {
    console.error("Failed to update profiles.is_premium:", error);
    // 一応 500 返しておく（必要なら 200 にしてもいい）
    return new Response("DB update error", { status: 500 });
  }

  console.log(`Updated profile ${appUserId} -> is_premium = ${isActive}`);

  return new Response("OK", { status: 200 });
});