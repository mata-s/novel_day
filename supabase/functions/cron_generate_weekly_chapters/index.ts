import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { generateWeeklyChapterFromEntries } from "../_shared/weekly_ai.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("SUPABASE_URL or SERVICE_ROLE_KEY is not set.");
}

const supabase = createClient(SUPABASE_URL!, SERVICE_ROLE_KEY!);

// ─────────────────────────────
// Deno.serve: cron から叩かれるエンドポイント
// ─────────────────────────────
Deno.serve(async (_req) => {
  try {
    const range = getLastWeekRangeJST();
    const { startKey, endKey, weekStartKey, weekOfMonth } = range;

    console.log(
      `Weekly cron: target range ${startKey} ~ ${endKey} (week_start=${weekStartKey}, weekOfMonth=${weekOfMonth})`,
    );

    // ① 自動生成 ON & プレミアムのユーザーを取得
    const { data: profiles, error: profilesError } = await supabase
      .from("profiles")
      .select("id, name, first_person")
      .eq("is_premium", true)
      .eq("auto_weekly_novel", true);

    if (profilesError) {
      console.error("profiles error", profilesError);
      return jsonRes(
        500,
        { error: "profiles fetch error", detail: profilesError.message },
      );
    }

    if (!profiles || profiles.length === 0) {
      console.log("no target users for weekly cron");
      return jsonRes(200, { message: "no target users" });
    }

    let processed = 0;
    let skippedNoDaily = 0;
    let skippedAlreadyExists = 0;
    let failed = 0;

    for (const p of profiles) {
      const userId = p.id as string;
      const firstPerson = (p.first_person as string | null) ?? "僕";
      const userName = (p.name as string | null) ?? null;

      console.log(`processing user: ${userId}`);

      // ② 先週 7 日分 daily を取得
      const { data: dailyList, error: dailyError } = await supabase
        .from("entries")
        .select("created_at, memo, body, writing_style, style")
        .eq("user_id", userId)
        .eq("chapter_type", "daily")
        .gte("date_key", startKey)
        .lte("date_key", endKey)
        .order("date_key", { ascending: true })
        .order("created_at", { ascending: true });

      if (dailyError) {
        console.error("daily fetch error", userId, dailyError);
        failed++;
        continue;
      }

      if (!dailyList || dailyList.length === 0) {
        console.log(`user ${userId}: no daily entries for last week`);
        skippedNoDaily++;
        continue;
      }

      // ③ すでに weekly があるかチェック
      const { data: existingWeekly, error: weeklyError } = await supabase
        .from("entries")
        .select("id")
        .eq("user_id", userId)
        .eq("chapter_type", "weekly")
        .eq("week_start_date", weekStartKey)
        .maybeSingle();

      if (weeklyError) {
        console.error("weekly exists check error", userId, weeklyError);
        failed++;
        continue;
      }

      if (existingWeekly) {
        console.log(`user ${userId}: weekly already exists, skip`);
        skippedAlreadyExists++;
        continue;
      }

      // ④ これまでの weekly 件数から「第◯巻」を決める
      const { data: weeklyList, error: weeklyListError } = await supabase
        .from("entries")
        .select("id")
        .eq("user_id", userId)
        .eq("chapter_type", "weekly");

      if (weeklyListError) {
        console.error("weekly list error", userId, weeklyListError);
        failed++;
        continue;
      }

      const volumeNumber = (weeklyList?.length ?? 0) + 1;

      // ⑤ 共通 AI 関数で weekly 本文を生成
      try {
        const { title: aiTitle, body } = await generateWeeklyChapterFromEntries(
          dailyList,
          {
            first_person: firstPerson,
            name: userName,
          },
        );

        // アプリ側のタイトルルールを優先
        const finalTitle = `第${weekOfMonth}週 まとめ章 第${volumeNumber}巻`;

        // ⑥ entries に weekly として保存
        const { error: insertError } = await supabase.from("entries").insert({
          user_id: userId,
          memo: `第${weekOfMonth}週 まとめ章`,
          style: "W",
          title: finalTitle,
          body,
          chapter_type: "weekly",
          week_start_date: weekStartKey,
          volume: volumeNumber,
          created_at: new Date().toISOString(),
        });

        if (insertError) {
          console.error("insert weekly error", userId, insertError);
          failed++;
          continue;
        }

        processed++;
      } catch (e) {
        console.error("AI generate weekly failed", userId, e);
        failed++;
        continue;
      }
    }

    return jsonRes(200, {
      message: "weekly cron finished",
      range: { startKey, endKey, weekStartKey, weekOfMonth },
      stats: {
        target: profiles.length,
        processed,
        skippedNoDaily,
        skippedAlreadyExists,
        failed,
      },
    });
  } catch (e) {
    console.error("cron error", e);
    return jsonRes(500, { error: "unexpected error", detail: String(e) });
  }
});

// ─────────────────────────────
// JST の「先週 7 日間 (Mon〜Sun)」を計算
// ─────────────────────────────
function getLastWeekRangeJST() {
  const now = new Date();
  const nowJST = toJST(now);

  // nowJST の「今週の月曜」
  const day = nowJST.getDay(); // 0:Sun, 1:Mon, ...
  const diffToMonday = (day + 6) % 7; // 月曜からの経過日数
  const thisMonday = new Date(
    nowJST.getFullYear(),
    nowJST.getMonth(),
    nowJST.getDate() - diffToMonday,
  );

  // 先週の月曜・日曜
  const lastMonday = new Date(
    thisMonday.getFullYear(),
    thisMonday.getMonth(),
    thisMonday.getDate() - 7,
  );
  const lastSunday = new Date(
    lastMonday.getFullYear(),
    lastMonday.getMonth(),
    lastMonday.getDate() + 6,
  );

  const startKey = formatDateKey(lastMonday);
  const endKey = formatDateKey(lastSunday);
  const weekStartKey = startKey;
  const weekOfMonth = calcWeekOfMonth(lastMonday);

  return {
    startDate: lastMonday,
    endDate: lastSunday,
    startKey,
    endKey,
    weekStartKey,
    weekOfMonth,
  };
}

function toJST(date: Date): Date {
  const utc = date.getTime() + date.getTimezoneOffset() * 60000;
  return new Date(utc + 9 * 60 * 60000); // +9h
}

function formatDateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

// 月の第何週か（Flutter の _weekOfMonth と同じイメージで）
function calcWeekOfMonth(d: Date): number {
  const first = new Date(d.getFullYear(), d.getMonth(), 1);
  const firstDay = first.getDay(); // 0=Sun

  // 月曜を週の始まりとしたときのオフセット
  const offset = (firstDay + 6) % 7;

  return Math.floor((d.getDate() + offset - 1) / 7) + 1;
}

function jsonRes(status: number, obj: unknown): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}