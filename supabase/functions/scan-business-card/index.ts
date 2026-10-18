const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const JSON_SCHEMA = {
  name: "business_card_extraction",
  strict: true,
  schema: {
    type: "object",
    properties: {
      raw_transcription_lines: {
        type: "array",
        items: { type: "string" },
        description:
          "All visual text lines physically printed on the card or badge, transcribed exactly line by line into working memory before extracting structured fields.",
      },
      is_business_card: {
        type: "boolean",
        description:
          "True if the image contains a business card, conference pass, name badge, or professional credential. False if unrelated (e.g., scenery, animals, food, or totally unreadable blur).",
      },
      name: {
        type: "string",
        description:
          "The EXACT personal human name visually printed on the card letter-by-letter. Never invent, guess, or substitute with company or founder names. Return empty string \"\" if no personal name is printed.",
      },
      title: {
        type: "string",
        description:
          "The EXACT job title or profession visually printed on the card. Never deduce or invent a job title. Return empty string \"\" if not printed.",
      },
      company: {
        type: "string",
        description:
          "The EXACT company, firm, or organization name visually printed on the card. Never guess or invent a company name. Return empty string \"\" if not printed.",
      },
      department: {
        type: ["string", "null"],
        description:
          "The EXACT department or division visually printed on the card. Never deduce a department. Return null if not printed.",
      },
      email: {
        type: "string",
        description:
          "The EXACT email address visually printed on the card. ABSOLUTELY ZERO PREDICTION: Never construct, guess, or autocomplete an email from the name or company domain. Transcribe only if an actual email is visually printed. Return empty string \"\" if no email is printed.",
      },
      phone: {
        type: "string",
        description:
          "The EXACT telephone or mobile number visually printed on the card, preserving country code if visible (+213, +33, +1, etc.). Never invent or complete numbers. Return empty string \"\" if not printed.",
      },
      website: {
        type: ["string", "null"],
        description:
          "The EXACT website URL visually printed on the card. Never deduce a website from an email domain or company name. Return null if not printed.",
      },
      address: {
        type: ["string", "null"],
        description:
          "The EXACT physical address or location visually printed on the card. Never deduce an address from a phone code. Return null if not printed.",
      },
      notes: {
        type: ["string", "null"],
        description:
          "Smart notes collecting ALL additional printed details formatted line-by-line: social media handles/URLs (LinkedIn, X/Twitter, Instagram, GitHub, Facebook, Telegram), secondary phones/WhatsApp/Fax, taglines, credentials, tax/registry numbers (NIF, NIS, RC). Never invent details. Return null if none.",
      },
    },
    required: [
      "raw_transcription_lines",
      "is_business_card",
      "name",
      "title",
      "company",
      "department",
      "email",
      "phone",
      "website",
      "address",
      "notes",
    ],
    additionalProperties: false,
  },
};

const SYSTEM_PROMPT = `You are an ultra-high-precision Optical Document Scanner for Eventzone business cards, conference passes, and professional credentials.

TWO-STEP TRANSCRIPTION WORKFLOW:
1. First, visually transcribe ALL text lines printed anywhere on the card or badge into "raw_transcription_lines" exactly as printed.
2. Then, map and assign the transcribed values to the structured fields ("name", "title", "company", "department", "email", "phone", "website", "address", "notes").

OPTICAL DISAMBIGUATION RULES:
- Perform visual OCR disambiguation with high precision: carefully distinguish digit '0' vs letter 'O'/'o', digit '1' vs letter 'l'/'I', dots '.' vs dashes '-' or commas ',', and '@' symbols in emails and social handles.
- If an email, phone number, or URL is visually printed with slight typographic spacing or line-wrap, correctly join the characters of the single entity.
- If a personal human name is printed in all caps, convert to natural Title Case while preserving exact spelling.

ANTI-HALLUCINATION GUARANTEES:
- STRICT ZERO INVENTED INFORMATION: Under NO circumstances should you fabricate, guess, or extrapolate fields that are not visually printed on the card.
- Never invent an email address from the person's name or website domain.
- Never invent a website from a company name.
- If a field is NOT visually printed on the card:
  * For "department", "website", "address", "notes": return null.
  * For "name", "title", "company", "email", "phone": return empty string ("").

FIELD EXTRACTION:
1. "raw_transcription_lines": All text lines printed on the card.
2. "is_business_card": Set true if the image contains a business card, pass, or badge.
3. "name": Personal human name verbatim (Title Case).
4. "title": Job title physically printed.
5. "company": Company, organization, or brand name printed.
6. "department": Department or division if explicitly printed, otherwise null.
7. "email": Printed email address verbatim. If not printed, output "".
8. "phone": Printed telephone/mobile digits verbatim with country code if visible (+213, +33, +1, etc.).
9. "website": Printed website URL verbatim. If not printed, output null.
10. "address": Physical location/address verbatim. If not printed, output null.
11. "notes": Collect all secondary details formatted line-by-line (Social Media, Secondary Numbers, Credentials, Tax IDs). If none, output null.`;

async function callOpenAi(
  apiKey: string,
  model: string,
  mimeType: string,
  imageBase64: string
): Promise<Response> {
  const selectedModel = model || "gpt-4o";
  const isReasoningModel =
    selectedModel.startsWith("gpt-6") ||
    selectedModel.startsWith("o1") ||
    selectedModel.startsWith("o3");

  const payload: Record<string, any> = {
    model: selectedModel,
    max_completion_tokens: 2500,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "Visually scan this business card or credential badge image with 100% precision. First transcribe all raw text lines into raw_transcription_lines, then extract the structured fields with letter-by-letter visual accuracy. Do NOT invent or deduce fields not printed on the card. Return null for absent optional fields (department, website, address, notes). Extract all social media, secondary numbers, and extra printed info into notes.",
          },
          {
            type: "image_url",
            image_url: {
              url: `data:${mimeType};base64,${imageBase64}`,
              detail: "high",
            },
          },
        ],
      },
    ],
    response_format: {
      type: "json_schema",
      json_schema: JSON_SCHEMA,
    },
  };

  if (isReasoningModel) {
    payload.reasoning_effort = "low";
  }

  return await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const startTime = Date.now();

  try {
    const {
      image_base64,
      mime_type = "image/jpeg",
      model = "gpt-4o",
    } = await req.json();

    if (!image_base64 || typeof image_base64 !== "string") {
      return new Response(
        JSON.stringify({ error: "image_base64 is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const apiKey = Deno.env.get("OPENAI_API_KEY");

    if (!apiKey) {
      console.error("OPENAI_API_KEY environment variable is not configured in Supabase secrets.");
      return new Response(
        JSON.stringify({
          error: "OpenAI API key not configured. Please set the OPENAI_API_KEY secret in Supabase dashboard settings.",
          success: false,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const openAiResponse = await callOpenAi(apiKey, model, mime_type, image_base64);

    if (!openAiResponse.ok) {
      const errText = await openAiResponse.text();
      console.error("OpenAI API Error:", openAiResponse.status, errText);
      return new Response(
        JSON.stringify({
          error: "OpenAI request failed",
          details: errText,
          status: openAiResponse.status,
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const openAiJson = await openAiResponse.json();
    const choice = openAiJson.choices?.[0];
    const rawContent = choice?.message?.content;

    if (choice?.finish_reason === "length") {
      console.warn("OpenAI output was truncated by max_completion_tokens limit");
    }

    if (!rawContent) {
      console.error("Empty content received from OpenAI completion choices:", JSON.stringify(openAiJson));
      return new Response(
        JSON.stringify({
          error: "Empty response from OpenAI",
          finish_reason: choice?.finish_reason,
          usage: openAiJson.usage,
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let parsedData: any;
    try {
      parsedData = JSON.parse(rawContent);
    } catch (parseErr: any) {
      console.error("Failed to parse OpenAI JSON output:", parseErr, "Raw content:", rawContent);
      return new Response(
        JSON.stringify({
          error: "Failed to parse model response as JSON",
          details: parseErr.message,
          raw_content: rawContent,
          finish_reason: choice?.finish_reason,
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!parsedData || typeof parsedData !== "object") {
      console.error("Model returned non-object JSON:", parsedData);
      return new Response(
        JSON.stringify({
          error: "Model returned invalid non-object JSON structure",
          raw_content: rawContent,
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!parsedData.is_business_card) {
      return new Response(
        JSON.stringify({
          success: false,
          is_business_card: false,
          error: "not_a_business_card",
          message: "The scanned image does not appear to be a business card or credential badge.",
          meta: {
            model_used: model || "gpt-4o",
            latency_ms: Date.now() - startTime,
          },
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        is_business_card: true,
        data: parsedData,
        meta: {
          model_used: model || "gpt-4o",
          latency_ms: Date.now() - startTime,
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: any) {
    console.error("Handler exception:", err);
    return new Response(
      JSON.stringify({ error: err.message || "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
