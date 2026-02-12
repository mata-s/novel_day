const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

if (!OPENAI_API_KEY) {
  console.error("OPENAI_API_KEY is not set in environment variables.");
}

/**
 * entries + persona から 週まとめの { title, body } を生成する共通関数
 */
export async function generateWeeklyChapterFromEntries(
  entries: any[],
  persona?: { first_person?: string | null; name?: string | null },
): Promise<{ title: string; body: string }> {
  if (!Array.isArray(entries) || entries.length === 0) {
    throw new Error("entries is required and must be non-empty");
  }

  const dominantStyle = inferDominantStyle(entries);

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
ユーザーの1週間分のエピソードをもとに、「第○週 まとめ章」を書いてください。

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
    throw new Error("OpenAI API error");
  }

  const completionJson = await completionRes.json();
  const content = completionJson.choices?.[0]?.message?.content;

  let title = "第○週 まとめ章";
  let body = "";

  try {
    const parsed = typeof content === "string" ? JSON.parse(content) : content;
    if (parsed) {
      title = parsed.title ?? title;
      body = parsed.body ?? "";
    }
  } catch (_e) {
    body = typeof content === "string" ? content : JSON.stringify(content);
  }

  return { title, body };
}

/**
 * 1週間分の entries から、その週の「気分の平均」として支配的な文体スタイルを推定する。
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