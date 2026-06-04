type ReflectionQuestionResult =
  | { status: "generated"; questions: string[] }
  | { status: "configuration_missing"; missing: "GROQ_API_KEY" };

export async function generateReflectionQuestions(
  entries: string[],
): Promise<ReflectionQuestionResult> {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) {
    return { status: "configuration_missing", missing: "GROQ_API_KEY" };
  }

  const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: process.env.GROQ_REFLECTION_MODEL ?? "llama-3.3-70b-versatile",
      messages: [
        {
          role: "system",
          content:
            "You generate three short, gentle reflection questions for a private journal. Return JSON only: {\"questions\":[\"...\"]}. Do not summarize the journal.",
        },
        {
          role: "user",
          content: JSON.stringify({ entries }),
        },
      ],
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    throw new Error(`REFLECTION_PROVIDER_${response.status}`);
  }
  const json = await response.json();
  const content = json.choices?.[0]?.message?.content;
  const parsed = JSON.parse(content);
  return {
    status: "generated",
    questions: parsed.questions
      .slice(0, 3)
      .map((q: string) => q.trim())
      .filter(Boolean),
  };
}
