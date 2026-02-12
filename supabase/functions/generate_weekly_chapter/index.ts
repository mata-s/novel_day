// supabase/functions/generate_weekly_chapter/index.ts
// 1週間分のエピソードから「第○週 まとめ章」を生成

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

if (!OPENAI_API_KEY) {
  console.error("OPENAI_API_KEY is not set in environment variables.");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Only POST is allowed" }),
      { status: 405, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const { entries, persona } = await req.json();

    if (!Array.isArray(entries) || entries.length === 0) {
      return new Response(
        JSON.stringify({ error: "entries is required and must be non-empty" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const dominantStyle = inferDominantStyle(entries);

    const occupation =
      persona &&
      typeof persona.occupation === "string" &&
      persona.occupation.trim().length > 0
        ? persona.occupation.trim()
        : "";

    const freeContext =
      persona &&
      typeof persona.freeContext === "string" &&
      persona.freeContext.trim().length > 0
        ? persona.freeContext.trim()
        : "";

    const firstPerson =
      persona && typeof persona.first_person === "string" && persona.first_person.trim().length > 0
        ? persona.first_person.trim()
        : "僕";

    const name =
      persona && typeof persona.name === "string" && persona.name.trim().length > 0
        ? persona.name.trim()
        : "";

    const occupationPart = occupation
      ? `- 仕事・役割: ${occupation}（生活の背景や一日のリズムをイメージするためのヒントです）`
      : "- 仕事・役割についての特別な指定はありません。";

    const freeContextPart = freeContext
      ? `- 日常の背景メモ: ${freeContext}`
      : "- 日常の背景メモは特に指定されていません。";

    const entriesText = entries
      .map((e: any) => {
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
${occupationPart}
${freeContextPart}

これらの情報は、その人の「暮らしの背景」や「心の置き場所」を考えるための手がかりとして使ってください。

- 日記の内容と自然につながる場合は、仕事・役割や背景メモに関係する描写を、
  本文のどこかで1回以上さりげなく入れてください。
- ただし、新しい具体的事実（特定の会社名・店名・人物名・出来事など）を
  勝手に付け加えてはいけません。
- 「コンビニのバイト」「ホテル清掃」「事務」など、誰でも連想できる一般的な行為
  （商品を並べる / レジを閉める / 部屋を整える / 画面を閉じる など）だけを、
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
`;

    const systemPrompt = buildSystemPromptForWeekly(dominantStyle);

    const completionRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "gpt-4.1-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: prompt },
        ],
        temperature: 0.8,
      }),
    });

    if (!completionRes.ok) {
      const errText = await completionRes.text();
      console.error("OpenAI API error:", errText);
      return new Response(
        JSON.stringify({ error: "OpenAI API error", detail: errText }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    const completionJson = await completionRes.json();
    const content = completionJson.choices?.[0]?.message?.content;

    let title = "第○週 まとめ章";
    let body = "";

    try {
      const parsed = JSON.parse(content);
      title = parsed.title ?? title;
      body = parsed.body ?? "";
    } catch (_e) {
      body = typeof content === "string" ? content : JSON.stringify(content);
    }

    return new Response(
      JSON.stringify({ title, body }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("Function error:", e);
    return new Response(
      JSON.stringify({ error: "Unexpected error", detail: String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

/**
 * 1週間分の entries から、その週の「気分の平均」として支配的な文体スタイルを推定する。
 * - entries[i].style や entries[i].writing_style を見て、もっとも頻出したものを返す。
 * - 何もなければ undefined。
 */
function inferDominantStyle(entries: any[]): string | undefined {
  const counter: Record<string, number> = {};

  for (const e of entries) {
    const raw =
      (e?.style ??
        (e as { writing_style?: string | null }).writing_style) ?? null;

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
 * - A: やわらか文学系・現代カジュアル・少しファンタジー
 * - B: 詩的描写・夜の静けさ・やさしい日常
 * - C: どこか切ない・前向きポジティブ・物語風ファンタジー
 * - 未指定や不明な場合は A に寄せる。
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

  // A / soft = やわらか文学系・現代カジュアル・少しファンタジー
  if (upper === "A" || lower === "soft") {
    return (
      "あなたは日本語で、やわらか文学系・現代カジュアル・少しファンタジーの文体で短い章を書いていく作家です。" +
      baseTail
    );
  }

  // B / poetic = 詩的描写・夜の静けさ・やさしい日常
  if (upper === "B" || lower === "poetic") {
    return (
      "あなたは日本語で、詩的描写・夜の静けさ・やさしい日常の文体で短い章を書いていく作家です。" +
      "情景描写や静けさ、余韻を大切にしてください。" +
      baseTail
    );
  }

  // C / dramatic = どこか切ない・前向きポジティブ・物語風ファンタジー
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