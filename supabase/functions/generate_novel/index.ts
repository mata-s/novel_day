// supabase/functions/generate_novel/index.ts
// Deno Edge Function: メモ + スタイル(A/B/C) から短編小説を生成して返す

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
    const { memo, style, persona } = await req.json();

    if (!memo || typeof memo !== "string") {
      return new Response(
        JSON.stringify({ error: "memo is required" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    let styleLabel = "";
    if (style === "A") {
      styleLabel = "やわらか文学系・現代カジュアル・少しファンタジー";
    } else if (style === "B") {
      styleLabel = "詩的描写・夜の静けさ・やさしい日常";
    } else if (style === "C") {
      styleLabel = "どこか切ない・前向きポジティブ・物語風ファンタジー";
    } else {
      // フォールバック（未指定や不正値の場合はA系に寄せる）
      styleLabel = "やわらか文学系・現代カジュアル・少しファンタジー";
    }

    const firstPerson =
      persona && typeof persona.first_person === "string" && persona.first_person.trim().length > 0
        ? persona.first_person.trim()
        : "僕";

    const name =
      persona && typeof persona.name === "string" && persona.name.trim().length > 0
        ? persona.name.trim()
        : "";

    const prompt = `
あなたは、日本語で短い小説風テキストを書く作家です。
ユーザーが書いたメモ（日記の断片）をもとに、その日の「一章」を書いてください。

文体タイプ:
- 選択されたスタイル: ${style}
- スタイルの特徴: ${styleLabel}

スタイルの意味は次の通りです:
- A: やわらか文学系・現代カジュアル・少しファンタジー
- B: 詩的描写・夜の静けさ（ハルキ風）・やさしい日常
- C: どこか切ない系・前向きポジティブ系・物語風ファンタジー系

主人公の設定:
- 一人称: ${firstPerson}
- 名前: ${name || "（名前は必ずしも本文に出さなくてよい）"}

本文は必ずこの主人公の一人称で書いてください。
他の語り手や三人称に変えず、この人物視点の地の文で統一してください。

条件:
- 上記のスタイル説明に沿ったトーンとリズムで書いてください
- 文字数の目安: 120〜200文字程度
- 日常の出来事を少しだけドラマティックに、でもやりすぎない表現で
- メモに書かれている出来事や感情を大切にしつつ、情景描写と心情を足してください
- 「ですます調」ではなく、「〜した」「〜だった」のような地の文で書いてください

出力フォーマット:
必ず次のJSON形式で返してください（余計なテキストは書かないこと）:
{"title": "タイトル", "body": "本文"}

ユーザーのメモ:
${memo}
`;

    const completionRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "gpt-4.1-mini",
        messages: [
          { role: "system", content: "あなたは短い日本語小説を書くAIです。" },
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

    let title = "今日の物語";
    let body = "";

    try {
      // content が JSON文字列として返ってくる前提
      const parsed = JSON.parse(content);
      title = parsed.title ?? title;
      body = parsed.body ?? "";
    } catch (_e) {
      // JSON パースに失敗した場合は、そのまま本文として使う
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