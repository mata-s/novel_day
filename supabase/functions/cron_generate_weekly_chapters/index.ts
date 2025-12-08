// supabase/functions/cron_generate_weekly_chapters/index.ts

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!OPENAI_API_KEY || !SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Missing env vars.");
}

const supabase = createClient(SUPABASE_URL!, SERVICE_ROLE_KEY!, {
  auth: { persistSession: false },
});

function startOfWeek(dt: Date): Date {
  const weekday = dt.getUTCDay() === 0 ? 7 : dt.getUTCDay(); // 月:1 ... 日:7
  const base = new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate()));
  base.setUTCDate(base.getUTCDate() - (weekday - 1));
  return base;
}

Deno.serve(async (_req) => {
  try {
    const now = new Date();
    const thisWeekStart = startOfWeek(now);
    const lastWeekStart = new Date(thisWeekStart);
    lastWeekStart.setUTCDate(thisWeekStart.getUTCDate() - 7);
    const lastWeekEnd = new Date(thisWeekStart);
    lastWeekEnd.setUTCSeconds(thisWeekStart.getUTCSeconds() - 1);

    const lastWeekStartIso = lastWeekStart.toISOString();
    const lastWeekEndIso = lastWeekEnd.toISOString();
    const lastWeekStartDateStr = lastWeekStartIso.substring(0, 10); // YYYY-MM-DD

    // 1) 先週 daily のあるユーザー一覧
    const { data: usersRows, error: usersError } = await supabase
      .from("entries")
      .select("user_id")
      .eq("chapter_type", "daily")
      .gte("created_at", lastWeekStartIso)
      .lte("created_at", lastWeekEndIso)
      .neq("user_id", null);

    if (usersError) throw usersError;
    if (!usersRows || usersRows.length === 0) {
      return new Response(JSON.stringify({ message: "no daily entries last week" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const userIds = Array.from(new Set(usersRows.map((r: any) => r.user_id as string)));

    for (const userId of userIds) {
      // 2) そのユーザーが先週分 weekly をすでに持ってないかチェック
      const { data: weeklyExisting, error: weeklyCheckError } = await supabase
        .from("entries")
        .select("id")
        .eq("user_id", userId)
        .eq("chapter_type", "weekly")
        .eq("week_start_date", lastWeekStartDateStr)
        .maybeSingle();

      if (weeklyCheckError) {
        console.error("weeklyCheckError:", weeklyCheckError);
        continue;
      }
      if (weeklyExisting) {
        // もう先週分の特別章があるのでスキップ
        continue;
      }

      // 3) 先週の daily entries を取得
      const { data: dailyEntries, error: dailyError } = await supabase
        .from("entries")
        .select("created_at, memo, body")
        .eq("user_id", userId)
        .eq("chapter_type", "daily")
        .gte("created_at", lastWeekStartIso)
        .lte("created_at", lastWeekEndIso)
        .order("created_at", { ascending: true });

      if (dailyError) {
        console.error("dailyError:", dailyError);
        continue;
      }
      if (!dailyEntries || dailyEntries.length === 0) {
        continue;
      }

      // 4) persona (first_person, name)
      const { data: profile, error: profileError } = await supabase
        .from("profiles")
        .select("first_person, name")
        .eq("id", userId)
        .maybeSingle();

      if (profileError) {
        console.error("profileError:", profileError);
      }

      const firstPerson =
        profile && profile.first_person && String(profile.first_person).trim().length > 0
          ? String(profile.first_person).trim()
          : "僕";
      const name =
        profile && profile.name && String(profile.name).trim().length > 0
          ? String(profile.name).trim()
          : "";

      // 5) プロンプト用テキスト整形（今の generate_weekly_chapter とほぼ同じ）
      const entriesText = (dailyEntries as any[])
        .map((e) => {
          const date = e.created_at ?? "";
          const memo = e.memo ?? "";
          const body = e.body ?? "";
          return `■ 日付: ${date}\n・メモ: ${memo}\n・小説: ${body}`;
        })
        .join("\n\n");

      const prompt = `
あなたは、日本語で短い小説風テキストを書く作家です。
ユーザーの1週間分のエピソードをもとに、「第○週 まとめ章（特別章）」を書いてください。

主人公の設定:
- 一人称: ${firstPerson}
- 名前: ${name || "（名前は本文に出してもし出さなくてもよい）"}

本文は必ずこの主人公の一人称で書いてください。
他の語り手や三人称に変えず、この人物視点の地の文で統一してください。

1週間の要素として意識してほしいこと:
- 今週の空気感（全体的にどんな1週間だったか）
- 心のトーンの変化（落ち込み・回復・ちいさな喜びなど）
- 食べたものの傾向（よく出てくる食べ物があればさりげなく登場させる）
- よく出てきたキーワードや場面（駅・空・雨・コーヒーなど）

条件:
- 文字数の目安: 400〜800文字程度
- 日常の出来事を少しだけドラマティックに、でもやりすぎない表現で
- 一週間を振り返る「まとめ章」として、読み終わったときに少しだけ前向きになれるトーンで
- 「ですます調」ではなく、「〜した」「〜だった」のような地の文で書いてください

出力フォーマット:
必ず次のJSON形式で返してください（余計なテキストは書かないこと）:
{"title": "タイトル", "body": "本文"}

対象の1週間の素材（メモと小説）は次の通りです:
${entriesText}
`;
      // 6) OpenAI呼び出し（今の index.ts と同じロジック）
      const completionRes = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${OPENAI_API_KEY}`,
        },
        body: JSON.stringify({
          model: "gpt-4.1-mini",
          messages: [
            { role: "system", content: "あなたは日本語で短い小説や章をまとめて書くAIです。" },
            { role: "user", content: prompt },
          ],
          temperature: 0.8,
        }),
      });

      if (!completionRes.ok) {
        console.error("OpenAI error:", await completionRes.text());
        continue;
      }

      const completionJson = await completionRes.json();
      const content = completionJson.choices?.[0]?.message?.content;
      let title = "第○週 特別章";
      let body = "";

      try {
        const parsed = JSON.parse(content);
        title = parsed.title ?? title;
        body = parsed.body ?? "";
      } catch (_e) {
        body = typeof content === "string" ? content : JSON.stringify(content);
      }

      // 7) weekly 章として entries に保存
      const { error: insertError } = await supabase.from("entries").insert({
        user_id: userId,
        memo: "第○週 まとめ章",
        style: "W",
        title,
        body,
        chapter_type: "weekly",
        week_start_date: lastWeekStartDateStr,
      });

      if (insertError) {
        console.error("insertError:", insertError);
      }
    }

    return new Response(JSON.stringify({ message: "ok" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("cron function error:", e);
    return new Response(
      JSON.stringify({ error: "Unexpected error", detail: String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});