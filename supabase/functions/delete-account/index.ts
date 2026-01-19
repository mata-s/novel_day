// supabase/functions/delete-account/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    // 1) 呼び出し元ユーザーをJWTから特定（= 本人確認）
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // JWT検証用（ユーザー特定）
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
    const uid = userData.user.id;

    // 2) サービスロールでデータ削除（RLSを回避できる）
    const admin = createClient(supabaseUrl, serviceRoleKey);

    // entries 全削除（user_id カラムがあるので確実）
    {
      const { error } = await admin.from("entries").delete().eq("user_id", uid);
      if (error) throw error;
    }

    // profiles 削除（多くの設計で profiles.id = auth.uid）
    // もし profiles が user_id カラムなら、ここを eq("user_id", uid) に変更
    {
      const { error } = await admin.from("profiles").delete().eq("id", uid);
      if (error) {
        // profiles 側のキーが違うプロジェクトもあるので、念のため user_id でも試す
        const { error: error2 } = await admin.from("profiles").delete().eq("user_id", uid);
        if (error2) {
          // profiles が必須じゃないなら握りつぶしてもいいけど、まずはエラー返す
          throw error2;
        }
      }
    }

    // 3) Authユーザー削除（これがApple要件）
    {
      const { error } = await admin.auth.admin.deleteUser(uid);
      if (error) throw error;
    }

    return new Response(null, { status: 204 });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});