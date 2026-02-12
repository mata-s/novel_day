import {onSchedule} from "firebase-functions/v2/scheduler";
import {onRequest} from "firebase-functions/v2/https";
import {CloudTasksClient} from "@google-cloud/tasks";
import {createClient, SupabaseClient} from "@supabase/supabase-js";
import OpenAI from "openai";

const SUPABASE_URL = process.env.SUPABASE_URL ?? "";
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
const OPENAI_API_KEY = process.env.OPENAI_API_KEY ?? "";

// ローカルの解析時は空文字のままで進ませる
if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !OPENAI_API_KEY) {
  console.warn(
    "Supabase/OpenAI の環境変数が設定されていません。ローカル解析用の警告です。"
  );
}

// トップレベルでは Supabase クライアントを作らず、実行時に初期化する
let supabaseSingleton: SupabaseClient | null = null;

// OpenAI クライアントもトップレベルでは生成せず、必要になったタイミングで初期化
let openaiClient: OpenAI | null = null;

/**
 * 実行時に OpenAI クライアントを取得するヘルパー
 *
 * OPENAI_API_KEY が設定されていない場合はエラーを投げます。
 *
 * @return {OpenAI} 初期化済みの OpenAI クライアント
 */
function getOpenAIClient(): OpenAI {
  if (!OPENAI_API_KEY) {
    throw new Error("OPENAI_API_KEY が設定されていません");
  }
  if (!openaiClient) {
    openaiClient = new OpenAI({apiKey: OPENAI_API_KEY});
  }
  return openaiClient;
}

// Supabase Row 型の簡易定義（型エラー回避用）
type ProfileRow = {
  id: string;
  name?: string | null;
  first_person?: string | null;
  occupation?: string | null;
  free_context?: string | null;
};

type WeeklyEntryRow = {
  user_id: string;
  memo: string;
  style: string;
  title: string;
  body: string;
  chapter_type: string;
  week_start_date: string;
  volume: number;
  created_at: string;
};

/**
 * 実行時に Supabase クライアントを取得するヘルパー
 *
 * @return {*} Supabase クライアント
 */
function getSupabaseClient() {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    throw new Error(
      "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY が設定されていません"
    );
  }

  if (!supabaseSingleton) {
    supabaseSingleton = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  }

  return supabaseSingleton;
}

// プロジェクトIDは Cloud Functions / Cloud Run 環境変数から拾う
const PROJECT_ID =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.GCP_PROJECT ||
  null;

if (!PROJECT_ID) {
  console.warn(
    "PROJECT_ID が環境変数に設定されていません。Cloud Tasks キューは作成できません。"
  );
}

let tasksClientSingleton: CloudTasksClient | null = null;

/**
 * 実行時に Cloud Tasks クライアントを取得するヘルパー
 *
 * Cloud Functions (Gen2) / Cloud Run 環境では、
 * トップレベルで CloudTasksClient を生成すると
 * コンテナ起動時に失敗するため、遅延初期化する。
 *
 * @return {CloudTasksClient} 初期化済みの Cloud Tasks クライアント
 */
function getTasksClient(): CloudTasksClient {
  if (!tasksClientSingleton) {
    tasksClientSingleton = new CloudTasksClient();
  }
  return tasksClientSingleton;
}

// Cloud Tasks のリージョン（キュー自体の場所）
const LOCATION = process.env.GCP_LOCATION || "asia-northeast1";
const QUEUE_ID = "novelday-weekly-novel";
const MONTHLY_QUEUE_ID = "novelday-monthly-novel";
// ========= 2. 毎月1日に「タスクを並べるだけ」の関数 =========
export const scheduleMonthlyNovelTasks = onSchedule(
  {
    // 毎月1日の 01:00 (JST) に実行
    schedule: "0 3 1 * *",
    timeZone: "Asia/Tokyo",
    region: "us-central1",
    timeoutSeconds: 120,
    secrets: [
      "SUPABASE_URL",
      "SUPABASE_SERVICE_ROLE_KEY",
      "OPENAI_API_KEY",
    ],
  },
  async () => {
    if (!PROJECT_ID) {
      console.error(
        "PROJECT_ID が未設定のため、scheduleMonthlyNovelTasks をスキップします。",
      );
      return;
    }

    const supabase = getSupabaseClient();

    const {monthStartKey, nextMonthStartKey, monthLabel} =
      getLastMonthRangeJST();

    console.log("monthly cron range", {
      monthStartKey,
      nextMonthStartKey,
      monthLabel,
    });

    const {data: profilesRaw, error: profilesError} = await supabase
      .from("profiles")
      .select("id, name, first_person")
      .eq("is_premium", true)
      .eq("auto_monthly_novel", true);

    if (profilesError) {
      console.error("profiles fetch error (monthly)", profilesError);
    }

    const profiles = (profilesRaw ?? []) as ProfileRow[];

    if (profiles.length === 0) {
      console.log("no target users for monthly cron");
      return;
    }

    const parent = getTasksClient().queuePath(
      PROJECT_ID,
      LOCATION,
      MONTHLY_QUEUE_ID,
    );

    for (const p of profiles) {
      const userId = p.id as string;

      const payload = {
        userId,
        monthStartKey,
        nextMonthStartKey,
        monthLabel,
      };

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: `https://us-central1-${PROJECT_ID}.cloudfunctions.net/generateMonthlyNovelWorker`,
          headers: {"Content-Type": "application/json"},
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
        },
      };

      await getTasksClient().createTask({parent, task});
      console.log("created monthly task for user", userId);
    }

    console.log("scheduleMonthlyNovelTasks finished", {
      count: profiles.length,
    });
  },
);

export const generateMonthlyNovelWorker = onRequest(
  {
    region: "us-central1",
    timeoutSeconds: 600,
    secrets: [
      "SUPABASE_URL",
      "SUPABASE_SERVICE_ROLE_KEY",
      "OPENAI_API_KEY",
    ],
  },
  async (req, res) => {
    try {
      const supabase = getSupabaseClient();

      if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
      }

      const {
        userId,
        monthStartKey,
        nextMonthStartKey,
        monthLabel,
      } = req.body as {
        userId?: string;
        monthStartKey?: string;
        nextMonthStartKey?: string;
        monthLabel?: string;
      };

      if (!userId || !monthStartKey || !nextMonthStartKey) {
        res.status(400).json({error: "invalid payload"});
        return;
      }

      console.log(
        "monthly worker start", {userId, monthStartKey, nextMonthStartKey}
      );

      const {data: dailyRaw, error: dailyError} = await supabase
        .from("entries")
        .select("created_at, memo, body, style")
        .eq("user_id", userId)
        .eq("chapter_type", "daily")
        .gte("date_key", monthStartKey)
        .lt("date_key", nextMonthStartKey)
        .order("date_key", {ascending: true})
        .order("created_at", {ascending: true});

      if (dailyError) {
        console.error("monthly daily fetch error", userId, dailyError);
        res.status(500).json({error: "monthly daily fetch error"});
        return;
      }

      if (!dailyRaw || dailyRaw.length === 0) {
        console.log("no monthly daily entries, skip", userId);
        res.status(200).json({status: "skipped_no_daily"});
        return;
      }

      const dailyList = dailyRaw as DailyEntryForAi[];

      const {data: existingMonthly, error: monthlyError} = await supabase
        .from("entries")
        .select("id")
        .eq("user_id", userId)
        .eq("chapter_type", "monthly")
        .eq("month_start_date", monthStartKey)
        .maybeSingle();

      if (monthlyError) {
        console.error("monthly exists check error", userId, monthlyError);
        res.status(500).json({error: "monthly exists check error"});
        return;
      }

      if (existingMonthly) {
        console.log("monthly already exists, skip", userId);
        res.status(200).json({status: "skipped_already_exists"});
        return;
      }

      const {data: profileRaw, error: profileError} = await supabase
        .from("profiles")
        .select("name, first_person, occupation, free_context")
        .eq("id", userId)
        .maybeSingle();

      const profile = (profileRaw ?? null) as ProfileRow | null;

      if (profileError) {
        console.error("monthly profile fetch error", userId, profileError);
      }

      const firstPerson =
        profile && typeof profile.first_person === "string" &&
        profile.first_person.trim() !== "" ?
          (profile.first_person as string) :
          "僕";

      const userName =
        profile && typeof profile.name === "string" &&
        profile.name.trim() !== "" ?
          (profile.name as string) :
          null;

      const occupation =
        typeof profile?.occupation === "string" &&
        profile.occupation.trim() !== "" ?
          profile.occupation :
          null;

      const ferrContext =
        typeof profile?.free_context === "string" &&
        profile.free_context.trim() !== "" ?
          profile.free_context :
          null;

      // ログ出力追加（月次ワーカー）
      console.log("monthly persona debug", {
        userId,
        firstPerson,
        userName,
        occupation,
        ferrContext,
      });

      const {title, body} = await generateMonthlyChapterFromEntriesNode(
        dailyList,
        {
          first_person: firstPerson,
          name: userName,
          occupation: occupation ?? null,
          ferrContext: ferrContext ?? null,
        },
      );

      const finalTitle = title ?? "今月の物語";
      const label = monthLabel ?? "";

      const monthlyRow = {
        user_id: userId,
        memo: label ? `${label}の短編` : "今月の短編",
        style: "M",
        title: finalTitle,
        body,
        chapter_type: "monthly",
        month_start_date: monthStartKey,
        created_at: new Date().toISOString(),
      };

      const {error: insertError} = await supabase
        .from("entries")
        .insert(monthlyRow as never);

      if (insertError) {
        console.error("insert monthly error", userId, insertError);
        res.status(500).json({error: "insert monthly error"});
        return;
      }

      console.log("monthly generated", {userId, monthStartKey});
      res.status(200).json({status: "ok"});
    } catch (e) {
      console.error("monthly worker unexpected error", e);
      res.status(500).json({error: "unexpected", detail: String(e)});
    }
  },
);

// ========= 1. 毎週月曜に「タスクを並べるだけ」の関数 =========
export const scheduleWeeklyNovelTasks = onSchedule(
  {
    schedule: "0 1 * * MON",
    timeZone: "Asia/Tokyo",
    region: "us-central1",
    timeoutSeconds: 120,
    secrets: [
      "SUPABASE_URL",
      "SUPABASE_SERVICE_ROLE_KEY",
      "OPENAI_API_KEY",
    ],
  },
  async () => {
    // 🔴 PROJECT_ID が取れてないなら安全にスキップ
    if (!PROJECT_ID) {
      console.error(
        "PROJECT_ID が未設定のため、scheduleWeeklyNovelTasks をスキップします。"
      );
      return;
    }

    const supabase = getSupabaseClient();

    const {startKey, endKey, weekStartKey, weekOfMonth} =
      getLastWeekRangeJST();

    console.log("weekly cron range", {
      startKey,
      endKey,
      weekStartKey,
      weekOfMonth,
    });

    const {data: profilesRaw, error: profilesError} = await supabase
      .from("profiles")
      .select("id, name, first_person")
      .eq("is_premium", true)
      .eq("auto_weekly_novel", true);

    if (profilesError) {
      console.error("profiles fetch error", profilesError);
    }

    const profiles = (profilesRaw ?? []) as ProfileRow[];

    if (profiles.length === 0) {
      console.log("no target users for weekly cron");
      return;
    }

    const parent = getTasksClient().queuePath(PROJECT_ID, LOCATION, QUEUE_ID);

    for (const p of profiles) {
      const userId = p.id as string;

      const payload = {
        userId,
        startKey,
        endKey,
        weekStartKey,
        weekOfMonth,
      };

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          // ⚠️ URL のリージョンは Cloud Functions のリージョン（us-central1）を使う
          url: `https://us-central1-${PROJECT_ID}.cloudfunctions.net/generateWeeklyNovelWorker`,
          headers: {"Content-Type": "application/json"},
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
        },
      };

      await getTasksClient().createTask({parent, task});
      console.log("created task for user", userId);
    }

    console.log("scheduleWeeklyNovelTasks finished", {
      count: profiles.length,
    });
  }
);


export const generateWeeklyNovelWorker = onRequest(
  {
    region: "us-central1",
    timeoutSeconds: 300,
    secrets: [
      "SUPABASE_URL",
      "SUPABASE_SERVICE_ROLE_KEY",
      "OPENAI_API_KEY",
    ],
  },
  async (req, res) => {
    try {
      const supabase = getSupabaseClient();

      if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
      }

      const {userId, startKey, endKey, weekStartKey, weekOfMonth} = req.body;

      if (!userId || !startKey || !endKey || !weekStartKey || !weekOfMonth) {
        res.status(400).json({error: "invalid payload"});
        return;
      }

      console.log("worker start", {userId, startKey, endKey});

      // ① daily 取得
      const {data: dailyList, error: dailyError} = await supabase
        .from("entries")
        .select("created_at, memo, body")
        .eq("user_id", userId)
        .eq("chapter_type", "daily")
        .gte("date_key", startKey)
        .lte("date_key", endKey)
        .order("date_key", {ascending: true})
        .order("created_at", {ascending: true});

      if (dailyError) {
        console.error("daily fetch error", userId, dailyError);
        res.status(500).json({error: "daily fetch error"});
        return;
      }

      if (!dailyList || dailyList.length === 0) {
        console.log("no daily entries, skip", userId);
        res.status(200).json({status: "skipped_no_daily"});
        return;
      }

      // ② 既に weekly があるかチェック
      const {data: existingWeekly, error: weeklyError} = await supabase
        .from("entries")
        .select("id")
        .eq("user_id", userId)
        .eq("chapter_type", "weekly")
        .eq("week_start_date", weekStartKey)
        .maybeSingle();

      if (weeklyError) {
        console.error("weekly exists check error", userId, weeklyError);
        res.status(500).json({error: "weekly exists check error"});
        return;
      }

      if (existingWeekly) {
        console.log("weekly already exists, skip", userId);
        res.status(200).json({status: "skipped_already_exists"});
        return;
      }

      // ③ プロフィール読み取り（人称・名前）
      const {data: profileRaw, error: profileError} = await supabase
        .from("profiles")
        .select("name, first_person, occupation, free_context")
        .eq("id", userId)
        .maybeSingle();

      const profile = (profileRaw ?? null) as ProfileRow | null;

      if (profileError) {
        console.error("profile fetch error", userId, profileError);
      }

      const firstPerson =
        profile && typeof profile.first_person === "string" &&
        profile.first_person.trim() !== "" ?
          (profile.first_person as string) :
          "僕";

      const userName =
        profile && typeof profile.name === "string" &&
        profile.name.trim() !== "" ?
          (profile.name as string) :
          null;

      const occupation =
        typeof profile?.occupation === "string" &&
        profile.occupation.trim() !== "" ?
          profile.occupation :
          null;

      const ferrContext =
        typeof profile?.free_context === "string" &&
        profile.free_context.trim() !== "" ?
          profile.free_context :
          null;

      // ログ出力追加（週次ワーカー）
      console.log("weekly persona debug", {
        userId,
        firstPerson,
        userName,
        occupation,
        ferrContext,
      });

      // ④ 既存 weekly 件数から「第◯巻」を決める
      const {data: weeklyList, error: weeklyListError} = await supabase
        .from("entries")
        .select("id")
        .eq("user_id", userId)
        .eq("chapter_type", "weekly");

      if (weeklyListError) {
        console.error("weekly list error", userId, weeklyListError);
        res.status(500).json({error: "weekly list error"});
        return;
      }

      const volumeNumber = (weeklyList?.length ?? 0) + 1;

      const {body} = await generateWeeklyChapterFromEntriesNode(
        dailyList,
        {
          first_person: firstPerson,
          name: userName,
          occupation: occupation ?? null,
          ferrContext: ferrContext ?? null,
        },
      );

      const finalTitle = `第${weekOfMonth}週 まとめ章 第${volumeNumber}巻`;

      const weeklyRow: WeeklyEntryRow = {
        user_id: userId,
        memo: `第${weekOfMonth}週 まとめ章`,
        style: "W",
        title: finalTitle,
        body,
        chapter_type: "weekly",
        week_start_date: weekStartKey,
        volume: volumeNumber,
        created_at: new Date().toISOString(),
      };

      const {error: insertError} = await supabase
        .from("entries")
        .insert(weeklyRow);

      if (insertError) {
        console.error("insert weekly error", userId, insertError);
        res.status(500).json({error: "insert weekly error"});
        return;
      }

      console.log("weekly generated", {userId, weekStartKey});
      res.status(200).json({status: "ok"});
    } catch (e) {
      console.error("worker unexpected error", e);
      res.status(500).json({error: "unexpected", detail: String(e)});
    }
  });

type DailyEntryForAi = {
  created_at: string;
  memo: string | null;
  body: string | null;
  style?: string | null;
};

type Persona = {
  first_person: string;
  name: string | null;
  occupation?: string | null;
  ferrContext?: string | null;
};

/**
 * 1ヶ月分の entries から短編小説を生成する（Edge Function と同じプロンプト仕様）。
 *
 * @param {DailyEntryForAi[]} entries 1ヶ月分のエントリ配列。
 * @param {Persona} persona  一人称・名前・仕事や日常背景などのペルソナ情報。
 * @return {Promise<{title: string, body: string}>}
 *   月の短編の { title, body } を含むオブジェクト。
 */
export async function generateMonthlyChapterFromEntriesNode(
  entries: DailyEntryForAi[],
  persona: Persona,
): Promise<{ title: string; body: string }> {
  if (!Array.isArray(entries) || entries.length === 0) {
    throw new Error("entries is required and must be non-empty");
  }

  const firstPerson =
    persona &&
    typeof persona.first_person === "string" &&
    persona.first_person.trim().length > 0 ?
      persona.first_person.trim() :
      "僕";

  const name =
    persona &&
    typeof persona.name === "string" &&
    persona.name.trim().length > 0 ?
      persona.name.trim() :
      undefined;

  const occupation =
  persona &&
  typeof persona.occupation === "string" &&
  persona.occupation.trim().length > 0 ?
    persona.occupation.trim() :
    "";

  const ferrContext =
  persona &&
  typeof persona.ferrContext === "string" &&
  persona.ferrContext.trim().length > 0 ?
    persona.ferrContext.trim() :
    "";

  const logs = entries
    .map((e) => {
      const date = e.created_at ?? "";
      const memo = (e.memo ?? "").toString().replace(/\s+/g, " ").trim();
      const body = (e.body ?? "").toString().replace(/\s+/g, " ").trim();

      const parts: string[] = [];
      parts.push(`日付: ${date}`);

      if (memo) {
        parts.push(`メモ: ${memo}`);
      }
      if (body) {
        parts.push(`短編の一部: ${body}`);
      }

      return "- " + parts.join(" / ");
    })
    .join("\n");

  const trimmedLogs =
    logs.length > 8000 ? logs.slice(0, 8000) + "\n...(省略)" : logs;

  const lengthHint = buildLengthHint(entries);

  const dominantStyle = inferDominantStyle(entries);

  const monthSummaryPrompt = createMonthlyPrompt(
    trimmedLogs,
    firstPerson,
    name,
    lengthHint,
    occupation,
    ferrContext,
  );

  const systemPrompt = buildSystemPromptForMonthly(dominantStyle);

  const openai = getOpenAIClient();

  const completion = await openai.chat.completions.create({
    model: "gpt-4.1",
    messages: [
      {
        role: "system",
        content: systemPrompt,
      },
      {
        role: "user",
        content: monthSummaryPrompt,
      },
    ],
    temperature: 0.8,
    max_tokens: 4000,
    response_format: {type: "json_object"},
  });

  const content = completion.choices[0]?.message?.content;

  if (!content) {
    throw new Error("モデルからの content が空でした");
  }

  const jsonText =
    typeof content === "string" ? content : JSON.stringify(content);

  let parsed: { title?: string; body?: string } = {};

  try {
    parsed = JSON.parse(jsonText);
  } catch (e1) {
    console.error(
      "generateMonthlyChapterFromEntriesNode: first JSON parse failed", e1
    );

    const match = jsonText.match(/\{[\s\S]*\}/);
    if (match) {
      const onlyJson = match[0];
      try {
        parsed = JSON.parse(onlyJson);
      } catch (e2) {
        console.error(
          "generateMonthlyChapterFromEntriesNode: second JSON parse failed",
          e2,
          "onlyJson preview:",
          onlyJson.slice(0, 300),
        );
        return {
          title: "今月の記録",
          body: jsonText.trim(),
        };
      }
    } else {
      console.error(
        "generateMonthlyChapterFromEntriesNode: JSON-like block not found.",
        jsonText.slice(0, 300),
      );
      return {
        title: "今月の記録",
        body: jsonText.trim(),
      };
    }
  }

  const title = parsed.title ?? "今月の物語";
  const body = parsed.body ?? "";

  return {title, body};
}

/**
 * 1ヶ月分のログから短編小説を作るためのプロンプトを組み立てる。
 *
 * @param {string} logs ログ全文（必要に応じてトリム済み）。
 * @param {string} firstPerson 一人称。
 * @param {string | undefined} userName ユーザー名（任意）。
 * @param {string} lengthHint 文字数の目安に関するヒント文。
 * @param {string} occupation ユーザーの仕事・役割（任意）。
 * @param {string} ferrContext 日常背景の自由メモ（任意）。
 * @return {string} 組み立てたプロンプト文字列。
 */
function createMonthlyPrompt(
  logs: string,
  firstPerson: string,
  userName: string | undefined,
  lengthHint: string,
  occupation: string,
  ferrContext: string,
): string {
  const namePart = userName ?
    `主人公の名前は「${userName}」ですが、無理に頻繁に出す必要はありません。` +
      "時々さりげなく出す程度で構いません。" :
    "主人公の名前は特に指定しません。";

  const occupationPart = occupation ?
    `- 仕事・役割: ${occupation}（生活の背景や一日のリズムをイメージするためのヒントです）` :
    "- 仕事・役割についての特別な指定はありません。";

  const ferrContextPart = ferrContext ?
    `- 日常の背景メモ: ${ferrContext}` :
    "- 日常の背景メモは特に指定されていません。";

  return `
以下は、ある1ヶ月のあいだに書かれた短い日記・短編のログです。

${logs}

参考情報（この1ヶ月の生活のヒント）:
${occupationPart}
${ferrContextPart}

これらの情報は、その人の「暮らしの背景」や「心の置き場所」を考えるための
手がかりとして使ってください。

- 日記の内容と自然につながる場合は、仕事・役割や背景メモに関係する描写を、
  本文のどこかで1回以上さりげなく入れてください。
- ただし、新しい具体的事実（特定の会社名・店名・人物名・出来事など）を
  勝手に付け加えてはいけません。
- 「コンビニのバイト」「ホテル清掃」「事務」など、誰でも連想できる一般的な
  行為（商品を並べる / レジを閉める / 部屋を整える / 画面を閉じる など）だけを、
  必要に応じて1〜2個まで描写してよいものとします。

この1ヶ月分の出来事や心の動きをもとに、

- 冒頭で「今月全体の空気感」を描き、
- 中盤で印象的だった出来事や、心の揺れ・変化を織り込み、
- 終盤で「この1ヶ月を少しだけ受け止めて、次の月へ進んでいく」ような余韻で締める

ひとつの連続した短編小説を、日本語で書いてください。

条件:
- 一人称は必ず「${firstPerson}」で統一してください。
- ${namePart}
- トーンは、静かでやさしく、ときどき少し切ない雰囲気で。
- 日記の具体的な出来事（食べ物、天気、人とのやりとりなど）を適度に拾いながら、
  「ひとつの物語」になるように再構成してください。
- ポジティブすぎず、ネガティブすぎず、「なんとか今日を生きている」感じの
  リアルさと、小さな希望を大事にしてください。
- 段落の先頭に全角スペース（「」）などの字下げを入れず、行頭からそのまま文章を
  書き始めてください。
- 改行のみで段落を区切り、字下げの有無が段落ごとに混在しないようにしてください。
- 終盤のまとめでは、「前に進んでいこう」「物語はまだ続いていく」などの
  紋切り型の前向きフレーズを多用しないでください。
- 希望や前向きさは、行動や情景の描写からほのかに伝わる程度にとどめてください。
- ${lengthHint}

出力は必ず JSON 形式で返してください。
以下の2つのキーだけを含めてください:

{
  "title": "短編小説としてのタイトル",
  "body": "短編小説の本文（改行込み）"
}
`;
}

/**
 * ログの量に応じて、モデルに伝える文字数の目安を変える。
 *
 * @param {DailyEntryForAi[]} entries 対象月のエントリ配列。
 * @return {string} 文字数の目安に関するヒント文。
 */
function buildLengthHint(entries: DailyEntryForAi[]): string {
  const count = entries.length;

  if (count <= 7) {
    return "文字数の目安は 2000〜3500字程度です。（多少前後しても構いません）";
  }

  if (count <= 20) {
    return "文字数の目安は 3500〜5500字程度です。（多少前後しても構いません）";
  }

  return "文字数の目安は 5000〜7500字程度です。（多少前後しても構いません）";
}

/**
 * 文体スタイル（A/B/C, soft/poetic/dramatic など）に応じて
 * モデルに渡す system プロンプトを組み立てる（月の短編用）。
 *
 * @param {string | undefined} style A/B/C などの文体スタイル。undefined の場合はデフォルト(A)を使う。
 * @return {string} OpenAI に渡す system ロール用のプロンプト文字列。
 */
function buildSystemPromptForMonthly(style: string | undefined): string {
  const baseTail =
    "与えられた1ヶ月分の日記ログをもとに、ひとつの連続した短編小説を作ります。" +
    "出力は必ず JSON 形式で { \"title\": string, \"body\": string } のみを返してください。" +
    "文章の段落は字下げせず、行頭に全角スペース（「　」）などを入れないでください。改行のみで段落を区切ってください。";

  if (!style) {
    return (
      "あなたは日本語で、やわらか文学系・現代カジュアル・少しファンタジーの文体で短編小説を書く作家です。" +
      baseTail
    );
  }

  const raw = style.trim();
  const upper = raw.toUpperCase();
  const lower = raw.toLowerCase();

  if (upper === "A" || lower === "soft") {
    return (
      "あなたは日本語で、やわらか文学系・現代カジュアル・少しファンタジーの文体で短編小説を書く作家です。" +
      baseTail
    );
  }

  if (upper === "B" || lower === "poetic") {
    return (
      "あなたは日本語で、詩的描写・夜の静けさ・やさしい日常の文体で短編小説を書く作家です。" +
      "情景描写や静けさ、余韻を大切にしてください。" +
      baseTail
    );
  }

  if (upper === "C" || lower === "dramatic") {
    return (
      "あなたは日本語で、どこか切ない・前向きポジティブ・物語風ファンタジーの文体で短編小説を書く作家です。" +
      "心の揺れやドラマ性を丁寧に描きながら、小さな希望が残るようにしてください。" +
      baseTail
    );
  }

  return (
    "あなたは日本語で、やわらか文学系・現代カジュアル・少しファンタジーの文体で短編小説を書く作家です。" +
    baseTail
  );
}

/**
 * Generate a weekly chapter (short story) from a list of daily diary entries.
 * Edge Function 側の generateWeeklyChapterFromEntries と同じプロンプト仕様で、
 * { title, body } を返す。
 *
 * @param {DailyEntryForAi[]} entries 1週間分のエントリ配列。
 * @param {Persona} persona  一人称・名前・仕事や日常背景などのペルソナ情報。
 * @return {Promise<object>} 週まとめの { title, body } を含むオブジェクト。
 */
export async function generateWeeklyChapterFromEntriesNode(
  entries: DailyEntryForAi[],
  persona: Persona,
): Promise<{ title: string; body: string }> {
  if (!Array.isArray(entries) || entries.length === 0) {
    throw new Error("entries is required and must be non-empty");
  }

  const dominantStyle = inferDominantStyle(entries);

  const firstPerson =
    persona &&
    typeof persona.first_person === "string" &&
    persona.first_person.trim().length > 0 ?
      persona.first_person.trim() :
      "僕";

  const name =
    persona &&
    typeof persona.name === "string" &&
    persona.name.trim().length > 0 ?
      persona.name.trim() :
      "";

  const occupation =
  persona &&
  typeof persona.occupation === "string" &&
  persona.occupation.trim().length > 0 ?
    persona.occupation.trim() :
    "";

  const ferrContext =
  persona &&
  typeof persona.ferrContext === "string" &&
  persona.ferrContext.trim().length > 0 ?
    persona.ferrContext.trim() :
    "";

  const entriesText = entries
    .map((e) => {
      const date = e.created_at ?? "";
      const memo = e.memo ?? "";
      const body = e.body ?? "";
      return `■ 日付: ${date}\n・メモ: ${memo}\n・小説: ${body}`;
    })
    .join("\n\n");

  const prompt = `
あなたは、日本語で短い小説風テキストを書く作家です。
ユーザーの1週間分のエピソードをもとに、「第○週 まとめ章」を書いてください。

主人公の設定:
- 一人称: ${firstPerson}
- 名前: ${name || "（名前は本文に出してもし出さなくてもよい）"}

本文は必ずこの主人公の一人称で書いてください。
他の語り手や三人称に変えず、この人物視点の地の文で統一してください。

参考情報（この1週間の生活のヒント）:
${occupation ?
    `- 仕事・役割: ${occupation}（生活の背景や一日のリズムをイメージするためのヒントです）` :
    "- 仕事・役割についての特別な指定はありません。"}
${ferrContext ?
    `- 日常の背景メモ: ${ferrContext}` :
    "- 日常の背景メモは特に指定されていません。"}

これらの情報は、その人の「暮らしの背景」や「心の置き場所」を考えるための
手がかりとして使ってください。

- 日記の内容と自然につながる場合は、仕事・役割や背景メモに関係する描写を、
  本文のどこかで1回以上さりげなく入れてください。
- ただし、新しい具体的事実（特定の会社名・店名・人物名・出来事など）を
  勝手に付け加えてはいけません。
- 「コンビニのバイト」「ホテル清掃」「事務」など、誰でも連想できる一般的な
  行為（商品を並べる / レジを閉める / 部屋を整える / 画面を閉じる など）だけを、
  必要に応じて1〜2個まで描写してよいものとします。

1週間の要素として意識してほしいこと:
- 先週の空気感（全体的にどんな1週間だったか）
- 心のトーンの変化（落ち込み・回復・ちいさな喜びなど）
- 食べたものの傾向（よく出てきた食べ物があればさりげなく登場）
- よく出てきたキーワードや場面（駅・空・雨・コーヒーなど）

条件:
- 文字数の目安: 400〜800文字程度
- 日常の出来事を少しだけドラマティックに、でもやりすぎない表現で
- 一週間を振り返る「まとめ章」として、読み終わったときに少しだけ前向きになれるトーンで
- 「ですます調」ではなく、「〜した」「〜だった」のような地の文で書いてください
- タイトルにダッシュ（— / ― / —— / ーー / -）や詩的な副題は使わず、素朴で説明的なタイトルにしてください。
- 段落冒頭に全角スペースや字下げは入れず、改行のみで段落を区切ってください。
- すべての段落でインデントの有無を統一してください。

出力フォーマット:
必ず次のJSON形式で返してください（余計なテキストは書かないこと）:
{"title": "タイトル", "body": "本文"}

対象の1週間の素材（メモと小説）は次の通りです:
${entriesText}
`.trim();

  const systemPrompt = buildSystemPromptForWeekly(dominantStyle);

  const openai = getOpenAIClient();

  const completion = await openai.chat.completions.create({
    model: "gpt-4.1-mini",
    messages: [
      {role: "system", content: systemPrompt},
      {role: "user", content: prompt},
    ],
    temperature: 0.8,
  });

  const content = completion.choices[0]?.message?.content ?? "";

  let title = "第○週 まとめ章";
  let body = "";

  try {
    const parsed = typeof content === "string" ? JSON.parse(content) : content;
    if (parsed) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const anyParsed = parsed as any;
      title = anyParsed.title ?? title;
      body = anyParsed.body ?? "";
    }
  } catch (_e) {
    body = typeof content === "string" ? content : JSON.stringify(content);
  }

  return {title, body};
}

/**
 * 1週間分の entries から、その週の「気分の平均」として支配的な文体スタイルを推定する。
 *
 * @param {DailyEntryForAi[]} entries 1週間分のエントリ配列。
 * @return {string | undefined} 最も頻出した文体スタイル。該当がない場合は undefined。
 */
function inferDominantStyle(entries: DailyEntryForAi[]): string | undefined {
  const counter: Record<string, number> = {};

  for (const e of entries) {
    const raw = e.style ?? null;
    if (!raw) continue;

    const key = String(raw).trim();
    if (!key) continue;

    counter[key] = (counter[key] ?? 0) + 1;
  }

  const list = Object.entries(counter);
  if (list.length === 0) return undefined;

  list.sort((a, b) => b[1] - a[1]);
  return list[0][0];
}

/**
 * 週の特別章用の system プロンプトを、A/B/C スタイルに合わせて組み立てる。
 *
 * @param {string | undefined} style A/B/C などの文体スタイル。undefined の場合はデフォルト(A)を使う。
 * @return {string} OpenAI に渡す system ロール用のプロンプト文字列。
 */
function buildSystemPromptForWeekly(style: string | undefined): string {
  const baseTail =
    "ユーザーの1週間分のエピソードをもとに、『第○週 まとめ章』となる短い小説風テキストを書きます。" +
    "出力は必ず JSON 形式で { \"title\": string, \"body\": string } のみを返してください。" +
    "タイトルは詩的にしすぎず、ダッシュや副題を使わないでください。" +
    "文章の段落は字下げせず、改行のみで統一してください。";

  if (!style) {
    return (
      "あなたは日本語で、やわらか文学系・現代カジュアル・少しファンタジーの文体で短い章を書いていく作家です。" +
      baseTail
    );
  }

  const raw = style.trim();
  const upper = raw.toUpperCase();
  const lower = raw.toLowerCase();

  if (upper === "A" || lower === "soft") {
    return (
      "あなたは日本語で、やわらか文学系・現代カジュアル・少しファンタジーの文体で短い章を書いていく作家です。" +
      baseTail
    );
  }

  if (upper === "B" || lower === "poetic") {
    return (
      "あなたは日本語で、詩的描写・夜の静けさ・やさしい日常の文体で短い章を書いていく作家です。" +
      "情景描写や静けさ、余韻を大切にしてください。" +
      baseTail
    );
  }

  if (upper === "C" || lower === "dramatic") {
    return (
      "あなたは日本語で、どこか切ない・前向きポジティブ・物語風ファンタジーの文体で短い章を書いていく作家です。" +
      "心の揺れやドラマ性を丁寧に描きながら、小さな希望が残るようにしてください。" +
      baseTail
    );
  }

  // 想定外 → A に寄せる
  return (
    "あなたは日本語で、やわらか文学系・現代カジュアル・少しファンタジーの文体で短い章を書いていく作家です。" +
    baseTail
  );
}

/**
 * Calculate the last full week range in JST, from Monday to Sunday.
 * The "last week" is defined relative to the current date.
 *
 * @return {{
 *   startDate: Date,
 *   endDate: Date,
 *   startKey: string,
 *   endKey: string,
 *   weekStartKey: string,
 *   weekOfMonth: number,
 * }} An object containing the date range and formatted keys for the last week.
 */
function getLastWeekRangeJST() {
  const now = new Date();
  const nowJST = toJST(now);

  const day = nowJST.getDay(); // 0:Sun, 1:Mon, ...
  const diffToMonday = (day + 6) % 7;
  const thisMonday = new Date(
    nowJST.getFullYear(),
    nowJST.getMonth(),
    nowJST.getDate() - diffToMonday,
  );

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

/**
 * Convert a given Date (assumed to be in the system time zone) into
 * Japan Standard Time (UTC+9) by applying a fixed offset.
 *
 * @param {Date} date - The original date.
 * @return {Date} A new Date adjusted to JST.
 */
function toJST(date: Date): Date {
  const utc = date.getTime() + date.getTimezoneOffset() * 60000;
  return new Date(utc + 9 * 60 * 60000);
}

/**
 * Format a Date into a YYYY-MM-DD string used as a date_key in Supabase.
 *
 * @param {Date} d - Date to format.
 * @return {string} The formatted date string.
 */
function formatDateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/**
 * Calculate the N-th week of the month for the given date.
 * Weeks are counted starting from 1, based on Monday-start weeks.
 *
 * @param {Date} d - Date within the target week.
 * @return {number} The week index in the month (1-based).
 */
function calcWeekOfMonth(d: Date): number {
  const first = new Date(d.getFullYear(), d.getMonth(), 1);
  const firstDay = first.getDay(); // 0=Sun
  const offset = (firstDay + 6) % 7;
  return Math.floor((d.getDate() + offset - 1) / 7) + 1;
}

/**
 * 直近1ヶ月分（先月）の範囲を JST ベースで計算する。
 *
 * @return {{
 *   monthStartDate: Date,
 *   nextMonthStartDate: Date,
 *   monthStartKey: string,
 *   nextMonthStartKey: string,
 *   monthLabel: string,
 * }} 先月1日と今月1日、およびフォーマット済みキーやラベル。
 */
function getLastMonthRangeJST() {
  const now = new Date();
  const nowJST = toJST(now);

  const thisMonthStart = new Date(
    nowJST.getFullYear(),
    nowJST.getMonth(),
    1,
  );

  const lastMonthStart = new Date(
    thisMonthStart.getFullYear(),
    thisMonthStart.getMonth() - 1,
    1,
  );

  const nextMonthStart = thisMonthStart;

  const monthStartKey = formatDateKey(lastMonthStart);
  const nextMonthStartKey = formatDateKey(nextMonthStart);

  const monthLabel = `${lastMonthStart.getFullYear()}年${
    lastMonthStart.getMonth() + 1
  }月`;

  return {
    monthStartDate: lastMonthStart,
    nextMonthStartDate: nextMonthStart,
    monthStartKey,
    nextMonthStartKey,
    monthLabel,
  };
}

