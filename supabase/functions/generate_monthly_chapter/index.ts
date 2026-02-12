// OpenAI クライアント（Edge Functions 用）
import OpenAI from "https://deno.land/x/openai@v4.24.0/mod.ts";

const openai = new OpenAI({
  apiKey: Deno.env.get("OPENAI_API_KEY") ?? "",
});

interface EntryForAi {
  created_at: string;
  memo?: string | null;
  body?: string | null;
  // その日の「文体スタイル」（例: "A", "B", "C" など）
  style?: string | null;
}

interface Persona {
  first_person?: string;
  name?: string | null;
  occupation?: string | null;
  freeContext?: string | null;
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

    const occupation = (persona?.occupation && String(persona.occupation).trim() !== "")
      ? String(persona.occupation)
      : undefined;

    const freeContext = (persona?.freeContext && String(persona.freeContext).trim() !== "")
      ? String(persona.freeContext)
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
      occupation,
      freeContext,
      lengthHint,
    );

    // その月の「気分の平均」＝もっとも頻出した文体スタイルを推定
    const dominantStyle = inferDominantStyle(entries);

    // 文体スタイルに応じた system プロンプトを組み立てる
    const systemPrompt = buildSystemPromptForMonthly(dominantStyle);

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
      // 月の短編をまとめて生成するため、少し余裕を持ったトークン数を確保
      max_tokens: 4000,
      // モデルの出力を必ず JSON オブジェクトにする
      response_format: { type: "json_object" },
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
      // まずは素直に JSON としてパースを試みる
      parsed = JSON.parse(jsonText);
    } catch (e1) {
      console.error(
        "generate_monthly_chapter: first JSON parse failed:",
        e1,
      );

      // よくあるケース:
      // - 先頭や末尾に説明文がつく
      // - ```json ... ``` で囲まれる
      // などなので、「最初の { から最後の } まで」を抜き出して再トライする
      const match = jsonText.match(/\{[\s\S]*\}/);
      if (match) {
        const onlyJson = match[0];
        try {
          parsed = JSON.parse(onlyJson);
        } catch (e2) {
          console.error(
            "generate_monthly_chapter: second JSON parse failed:",
            e2,
            "onlyJson preview:",
            onlyJson.slice(0, 300),
          );
          return new Response(
            JSON.stringify({
              error: "モデルの出力が JSON 形式として解釈できませんでした。（2回目のパースに失敗）",
            }),
            {
              status: 500,
              headers: { "Content-Type": "application/json" },
            },
          );
        }
      } else {
        console.error(
          "generate_monthly_chapter: JSON-like block not found. raw content preview:",
          jsonText.slice(0, 300),
        );

        // モデルが JSON を返さずプレーンテキストだけを返した場合のフォールバック。
        // エラーにはせず、そのテキスト全体を本文として返す。
        return new Response(
          JSON.stringify({
            title: "今月の記録",
            body: jsonText.trim(),
          }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        );
      }
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
  occupation: string | undefined,
  freeContext: string | undefined,
  lengthHint: string,
): string {
  const namePart = userName
    ? `主人公の名前は「${userName}」ですが、無理に頻繁に出す必要はありません。時々さりげなく出す程度で構いません。`
    : "主人公の名前は特に指定しません。";

  const occupationPart = occupation
    ? `仕事や役割として「${occupation}」があります。これは、その人がどのような` +
      "日常を送っているかを考えるためのヒントとして使ってください。"
    : "仕事や役割について特別な指定はありません。";

  const freeContextPart = freeContext
    ? "日常の背景メモ（自由記入）として、次のような情報があります: " +
      freeContext +
      "。文脈が自然につながる範囲で、心情や空気感の描写に活かしてくださ" +
      "い。"
    : "日常の背景メモは特に指定されていません。";

  return `
以下は、ある1ヶ月のあいだに書かれた短い日記・短編のログです。

${logs}

参考情報（この月の生活のヒント）:
- ${occupationPart}
- ${freeContextPart}

これらの情報は、その人の「暮らしの背景」や「心の置き場所」を考えるた
めの手がかりとして使ってください。

とくに次のルールに従ってください:
- 日記の内容と自然につながる場合は、仕事・役割や背景メモに関係する描写
  を、本文のどこかで1回以上さりげなく入れてください。
- ただし、新しい具体的事実（特定の会社名・店名・人物名・出来事など）を
  勝手に付け加えてはいけません。
- 「コンビニのバイト」「ホテル清掃」「事務」など、誰でも連想できる一般
  的な行為（商品を並べる / レジを閉める / 部屋を整える / 画面を閉じる
  など）だけを、必要に応じて1〜2個まで描写してよいものとします。

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
- 段落の先頭に全角スペース（「　」）などの字下げを入れず、行頭からそのまま文章を書き始めてください。改行のみで段落を区切り、字下げの有無が段落ごとに混在しないようにしてください。
- 終盤のまとめでは、「前に進んでいこう」「物語はまだ続いていく」などの紋切り型の前向きフレーズを多用しないでください。希望や前向きさは、行動や情景の描写からほのかに伝わる程度にとどめてください。
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

/**
 * 1ヶ月分のエントリから「その月の気分の平均」として支配的な文体スタイルを推定する
 * - もっとも頻出した style を返す
 * - style が1つも入っていなければ undefined
 */
function inferDominantStyle(entries: EntryForAi[]): string | undefined {
  const counter: Record<string, number> = {};

  for (const e of entries) {
    // DB 側のカラム名などに合わせて柔軟に拾えるようにしておく
    const raw =
      (e.style ??
        // 念のため別名もケア（将来のための保険）
        (e as unknown as { writing_style?: string | null }).writing_style) ??
      null;

    if (!raw) continue;

    const key = String(raw).trim();
    if (!key) continue;

    counter[key] = (counter[key] ?? 0) + 1;
  }

  const entriesOfCounter = Object.entries(counter);
  if (entriesOfCounter.length === 0) return undefined;

  // 最頻値を取る
  entriesOfCounter.sort((a, b) => b[1] - a[1]);
  return entriesOfCounter[0][0];
}

/**
 * 文体スタイル（A/B/C, soft/poetic/dramatic など）に応じて
 * モデルに渡す system プロンプトを組み立てる。
 *
 * - 今日のページで使っている style をそのまま流用する想定。
 * - スタイルが決められていない場合は、A 系（やわらか文学系）に寄せる。
 */
function buildSystemPromptForMonthly(style: string | undefined): string {
  const baseTail =
    "与えられた1ヶ月分の日記ログをもとに、ひとつの連続した短編小説を作ります。" +
    "出力は必ず JSON 形式で { \"title\": string, \"body\": string } のみを返してください。" +
    "文章の段落は字下げせず、行頭に全角スペース（「　」）などを入れないでください。改行のみで段落を区切ってください。";

  if (!style) {
    // デフォルトは A 系の世界観に寄せる
    return (
      "あなたは日本語で、やわらか文学系・現代カジュアル・少しファンタジーの文体で短編小説を書く作家です。" +
      baseTail
    );
  }

  const raw = style.trim();
  const upper = raw.toUpperCase();
  const lower = raw.toLowerCase();

  // A / soft = やわらか文学系・現代カジュアル・少しファンタジー
  if (upper === "A" || lower === "soft") {
    return (
      "あなたは日本語で、やわらか文学系・現代カジュアル・少しファンタジーの文体で短編小説を書く作家です。" +
      baseTail
    );
  }

  // B / poetic = 詩的描写・夜の静けさ・やさしい日常
  if (upper === "B" || lower === "poetic") {
    return (
      "あなたは日本語で、詩的描写・夜の静けさ・やさしい日常の文体で短編小説を書く作家です。" +
      "情景描写や静けさ、余韻を大切にしてください。" +
      baseTail
    );
  }

  // C / dramatic = どこか切ない・前向きポジティブ・物語風ファンタジー
  if (upper === "C" || lower === "dramatic") {
    return (
      "あなたは日本語で、どこか切ない・前向きポジティブ・物語風ファンタジーの文体で短編小説を書く作家です。" +
      "心の揺れやドラマ性を丁寧に描きながら、小さな希望が残るようにしてください。" +
      baseTail
    );
  }

  // 想定外 → A に寄せる
  return (
    "あなたは日本語で、やわらか文学系・現代カジュアル・少しファンタジーの文体で短編小説を書く作家です。" +
    baseTail
  );
}