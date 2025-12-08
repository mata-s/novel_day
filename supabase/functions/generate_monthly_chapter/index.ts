// supabase/functions/generate_monthly_chapter/index.ts

// OpenAI クライアント（Edge Functions 用）
import OpenAI from "https://deno.land/x/openai@v4.24.0/mod.ts";

const openai = new OpenAI({
  apiKey: Deno.env.get("OPENAI_API_KEY") ?? "",
});

interface EntryForAi {
  created_at: string;
  memo?: string | null;
  body?: string | null;
}

interface Persona {
  first_person?: string;
  name?: string | null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const { entries, persona } = (await req.json()) as {
      entries: EntryForAi[];
      persona?: Persona;
    };

    if (!entries || !Array.isArray(entries) || entries.length === 0) {
      return new Response(
        JSON.stringify({ error: "entries が空です" }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    const firstPerson = (persona?.first_person && String(persona.first_person).trim() !== "")
      ? String(persona.first_person)
      : "僕";

    const userName = (persona?.name && String(persona.name).trim() !== "")
      ? String(persona.name)
      : undefined;

    // ===== 1ヶ月分のログをテキストにまとめる =====
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

    // GPT に投げるテキストがあまりに長くなりすぎないように一応カット
    const trimmedLogs = logs.length > 8000 ? logs.slice(0, 8000) + "\n...(省略)" : logs;

    // ログの量に応じて、目安の文字数レンジを変える
    const lengthHint = buildLengthHint(entries, trimmedLogs);

    const monthSummaryPrompt = createMonthlyPrompt(
      trimmedLogs,
      firstPerson,
      userName,
      lengthHint,
    );

    const completion = await openai.chat.completions.create({
      model: "gpt-4.1",
      messages: [
        {
          role: "system",
          content:
            "あなたは日本語で静かな情緒のある短編小説を書く小説家です。" +
            "与えられた1ヶ月分の日記・短編ログをもとに、ひとつの連続した短編小説を作ります。" +
            "出力は必ず JSON 形式で、{ \"title\": string, \"body\": string } だけを含めてください。",
        },
        {
          role: "user",
          content: monthSummaryPrompt,
        },
      ],
      temperature: 0.8,
      max_tokens: 1800,
    });

    const choice = completion.choices[0];
    const content = choice.message.content;

    if (!content) {
      throw new Error("モデルからの content が空でした");
    }

    // 文字列として扱う（v4.24.0 は string のはず）
    const jsonText = typeof content === "string"
      ? content
      : JSON.stringify(content);

    let parsed: { title?: string; body?: string };

    try {
      parsed = JSON.parse(jsonText);
    } catch (_e) {
      // モデルが JSON 外の文章を返した場合の保険
      parsed = { title: "今月の物語", body: jsonText };
    }

    const title = parsed.title ?? "今月の物語";
    const body = parsed.body ?? "";

    return new Response(
      JSON.stringify({ title, body }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    console.error("generate_monthly_chapter error:", e);
    return new Response(
      JSON.stringify({ error: "月の短編生成中にエラーが発生しました" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});

/**
 * 1ヶ月分のログから短編小説を作るためのプロンプトを組み立てる
 */
function createMonthlyPrompt(
  logs: string,
  firstPerson: string,
  userName: string | undefined,
  lengthHint: string,
): string {
  const namePart = userName
    ? `主人公の名前は「${userName}」ですが、無理に頻繁に出す必要はありません。時々さりげなく出す程度で構いません。`
    : "主人公の名前は特に指定しません。";

  return `
以下は、ある1ヶ月のあいだに書かれた短い日記・短編のログです。

${logs}

この1ヶ月分の出来事や心の動きをもとに、

- 冒頭で「今月全体の空気感」を描き、
- 中盤で印象的だった出来事や、心の揺れ・変化を織り込み、
- 終盤で「この1ヶ月を少しだけ受け止めて、次の月へ進んでいく」ような余韻で締める

ひとつの連続した短編小説を、日本語で書いてください。

条件:
- 一人称は必ず「${firstPerson}」で統一してください。
- ${namePart}
- トーンは、静かでやさしく、ときどき少し切ない雰囲気で。
- 日記の具体的な出来事（食べ物、天気、人とのやりとりなど）を適度に拾いながら、「ひとつの物語」になるように再構成してください。
- ポジティブすぎず、ネガティブすぎず、「なんとか今日を生きている」感じのリアルさと、小さな希望を大事にしてください。
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
 * ログの量に応じて、モデルに伝える文字数の目安を変える
 * - 記録が少ない → 短め
 * - 普通 → 中くらい
 * - 多い → 少し長め
 */
function buildLengthHint(entries: EntryForAi[], logs: string): string {
  const count = entries.length;

  // ログがほとんどない場合
  if (count <= 7) {
    return "文字数の目安は 2000〜3500字程度です。（多少前後しても構いません）";
  }

  // 普通にそこそこ記録がある場合
  if (count <= 20) {
    return "文字数の目安は 3500〜5500字程度です。（多少前後しても構いません）";
  }

  // かなりしっかり書いている人向け
  return "文字数の目安は 5000〜7500字程度です。（多少前後しても構いません）";
}