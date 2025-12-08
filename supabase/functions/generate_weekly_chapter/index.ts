// supabase/functions/generate_weekly_chapter/index.ts
// 1週間分のエピソードから「第○週 特別章」を生成

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

    const firstPerson =
      persona && typeof persona.first_person === "string" && persona.first_person.trim().length > 0
        ? persona.first_person.trim()
        : "僕";

    const name =
      persona && typeof persona.name === "string" && persona.name.trim().length > 0
        ? persona.name.trim()
        : "";

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
ユーザーの1週間分のエピソードをもとに、「第○週 まとめ章（特別章）」を書いてください。

主人公の設定:
- 一人称: ${firstPerson}
- 名前: ${name || "（名前は本文に出してもし出さなくてもよい）"}

本文は必ずこの主人公の一人称で書いてください。
他の語り手や三人称に変えず、この人物視点の地の文で統一してください。

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

出力フォーマット:
必ず次のJSON形式で返してください（余計なテキストは書かないこと）:
{"title": "タイトル", "body": "本文"}

対象の1週間の素材（メモと小説）は次の通りです:
${entriesText}
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
          { role: "system", content: "あなたは日本語で短い小説や章をまとめて書くAIです。" },
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

    let title = "第○週 特別章";
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