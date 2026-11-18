import {
  allowRequest,
  authenticatedUser,
  corsHeaders,
  parsingContext,
  type ParsingContextInput,
  structureTask,
  validateImageURL,
} from "../_shared/task-parsing.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const DEFAULT_OCR_PROMPT =
  `Transcribe ALL legible text from this image accurately.
Preserve line breaks, numbers, dates, times, currency amounts, names, and addresses.
Output the raw transcription only — no commentary.
If the image is a calendar, transcribe the focused day cell and any adjacent context that helps interpret dates.
Correct obvious OCR confusions in Chinese handwriting when context is clear (e.g. 兴趣班, 缴费, 截止).`;

function jsonError(message: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: message }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

type TextChatMessage = {
  role: "system" | "user" | "assistant";
  content: string;
};

type MultimodalChatMessage = {
  role: "user";
  content: Array<
    { type: "text"; text: string } | {
      type: "image_url";
      image_url: { url: string };
    }
  >;
};

type RecognitionRegion = {
  top_left?: { x?: number; y?: number };
  top_right?: { x?: number; y?: number };
  bottom_left?: { x?: number; y?: number };
  bottom_right?: { x?: number; y?: number };
};

type RequestBody = ParsingContextInput & {
  image_url?: string;
  target_date?: string;
  recognition_region?: RecognitionRegion;
};

function buildOcrUserPrompt(body: RequestBody): string {
  const parts: string[] = [DEFAULT_OCR_PROMPT];

  const targetDate = typeof body.selected_calendar_day === "string"
    ? body.selected_calendar_day
    : (typeof body.target_date === "string"
      ? body.target_date.trim()
      : undefined);
  if (targetDate) {
    parts.push(
      `The user is creating a task for calendar day ${targetDate}. If this is a monthly calendar, focus on the cell for that day.`,
    );
  }

  const region = body.recognition_region;
  if (
    region?.top_left && region?.top_right && region?.bottom_left &&
    region?.bottom_right
  ) {
    const fmt = (p: { x?: number; y?: number }) =>
      `(${(p.x ?? 0).toFixed(3)}, ${(p.y ?? 0).toFixed(3)})`;
    parts.push(
      `Prioritize text inside the normalized image region with corners: ` +
        `top-left ${fmt(region.top_left)}, top-right ${
          fmt(region.top_right)
        }, ` +
        `bottom-left ${fmt(region.bottom_left)}, bottom-right ${
          fmt(region.bottom_right)
        } ` +
        `(coordinates 0–1 relative to image width/height).`,
    );
  }

  return parts.join("\n\n");
}

async function callChatCompletions(args: {
  baseUrl: string;
  apiKey: string;
  model: string;
  messages: Array<TextChatMessage | MultimodalChatMessage>;
  jsonMode?: boolean;
  label: string;
}): Promise<string> {
  const isGoogleNative = args.baseUrl.includes(
    "generativelanguage.googleapis.com",
  );

  if (isGoogleNative) {
    const cleanModel = args.model.replace(/^models\//, "");
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${cleanModel}:generateContent`;

    let promptText = DEFAULT_OCR_PROMPT;
    let base64Data = "";
    let mimeType = "image/jpeg";

    const userMsg = args.messages.find((m) => m.role === "user");
    if (userMsg && Array.isArray(userMsg.content)) {
      for (const item of userMsg.content) {
        if (item.type === "text" && item.text) promptText = item.text;
        if (item.type === "image_url" && item.image_url?.url) {
          const rawUrl = item.image_url.url;
          if (rawUrl.startsWith("data:")) {
            const matches = rawUrl.match(/^data:([^;]+);base64,(.+)$/);
            if (matches) {
              mimeType = matches[1];
              base64Data = matches[2].replace(/\s/g, "");
            }
          }
        }
      }
    }

    const response = await fetch(url, {
      method: "POST",
      signal: AbortSignal.timeout(30000),
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": args.apiKey,
      },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              { text: promptText },
              { inlineData: { mimeType: mimeType, data: base64Data } },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 2048,
        },
      }),
    });

    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      throw new Error(
        `${args.label} Google Native API ${response.status}: ${
          JSON.stringify(payload)
        }`,
      );
    }

    const content = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!content?.trim()) {
      throw new Error(
        `${args.label} Google API 返回空。可能是 Free Tier 遭到节点高并发限制，请等 5 秒重试。`,
      );
    }
    return content.trim();
  }

  const url = `${args.baseUrl.replace(/\/$/, "")}/chat/completions`;
  const response = await fetch(url, {
    method: "POST",
    signal: AbortSignal.timeout(30000),
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${args.apiKey}`,
    },
    body: JSON.stringify({
      model: args.model,
      messages: args.messages,
      ...(args.jsonMode ? { response_format: { type: "json_object" } } : {}),
      temperature: 0.1,
    }),
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    const apiMessage =
      (payload as { error?: { message?: string } })?.error?.message ??
        JSON.stringify(payload ?? {});
    throw new Error(`${args.label} API ${response.status}: ${apiMessage}`);
  }

  const content =
    (payload as { choices?: { message?: { content?: string } }[] })?.choices
      ?.[0]?.message?.content;
  if (!content?.trim()) {
    throw new Error(`${args.label} returned empty content.`);
  }
  return content.trim();
}

function resolveOcrConfig(): {
  baseUrl: string;
  apiKey: string;
  model: string;
} {
  const ocrKey = Deno.env.get("OCR_API_KEY")?.trim() || "";
  const baseUrl = "https://generativelanguage.googleapis.com";
  const model = Deno.env.get("OCR_MODEL")?.trim() || "gemini-2.5-flash";

  if (!ocrKey) {
    throw new Error(
      "OCR 阶段的 Gemini API Key 未配置。请运行 supabase secrets set OCR_API_KEY=...",
    );
  }

  return { baseUrl, apiKey: ocrKey, model };
}

async function fetchImageAsDataUrl(imageUrl: string): Promise<string> {
  const url = validateImageURL(imageUrl, Deno.env.get("SUPABASE_URL") ?? "");
  const res = await fetch(url, {
    signal: AbortSignal.timeout(15000),
    redirect: "error", // Never follow an otherwise trusted URL to an internal service.
  });
  if (!res.ok) throw new Error(`Image fetch failed (HTTP ${res.status})`);
  const mime = res.headers.get("content-type")?.split(";")[0]?.trim() ||
    "image/jpeg";
  if (!/^image\/(jpeg|png|webp|heic|heif)$/i.test(mime)) {
    throw new Error("Invalid image type");
  }
  const maximumBytes = 12 * 1024 * 1024;
  if (Number(res.headers.get("content-length")) > maximumBytes) {
    await res.body?.cancel();
    throw new Error("Image too large");
  }
  if (!res.body) throw new Error("Empty image");
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > maximumBytes) throw new Error("Image too large");
      chunks.push(value);
    }
  } finally {
    await reader.cancel();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const value of chunks) {
    bytes.set(value, offset);
    offset += value.length;
  }
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return `data:${mime};base64,${btoa(binary)}`;
}

async function ocrExtractFromImage(
  dataUrl: string,
  body: RequestBody,
): Promise<{
  text: string;
}> {
  const ocr = resolveOcrConfig();
  const ocrPrompt = buildOcrUserPrompt(body);

  let extractedText = "";
  const maxRetries = 3;
  let delay = 1000; // 初始等待 1 秒

  for (let i = 0; i < maxRetries; i++) {
    try {
      console.log(
        `[parse-create-task-from-images] Gemini Native Stage Attempt ${
          i + 1
        }/${maxRetries}`,
      );

      extractedText = await callChatCompletions({
        baseUrl: ocr.baseUrl,
        apiKey: ocr.apiKey,
        model: ocr.model,
        label: "OCR-Stage1-GeminiNative",
        messages: [
          {
            role: "user",
            content: [
              { type: "image_url", image_url: { url: dataUrl } },
              { type: "text", text: ocrPrompt },
            ],
          },
        ],
      });

      break; // 🌟 成功拿到数据，立刻跳出循环
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      // 🌟 如果判定为 Google 503 或者是免费层频控，触发指数退避等待
      if (
        (msg.includes("503") || msg.includes("UNAVAILABLE")) &&
        i < maxRetries - 1
      ) {
        console.warn(
          `[Gemini 503 Overload] Server busy. Retrying in ${delay}ms...`,
        );
        await new Promise((resolve) => setTimeout(resolve, delay));
        delay *= 2; // 延迟翻倍：1s -> 2s -> 4s
      } else {
        throw error; // 其他致命错误（如 401 或最后一次失败）直接抛出
      }
    }
  }

  return { text: extractedText };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") return jsonError("Method not allowed", 405);
  try {
    const userId = await authenticatedUser(req);
    if (!userId) return jsonError("Unauthorized", 401);
    if (!allowRequest(userId)) return jsonError("Too many requests", 429);
    let body: RequestBody;
    try {
      body = await req.json();
    } catch {
      return jsonError("Invalid JSON body");
    }

    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return jsonError("Invalid body");
    }
    let context: string;
    try {
      context = parsingContext(body);
    } catch {
      return jsonError("Invalid parsing context");
    }
    const imageUrl = typeof body.image_url === "string"
      ? body.image_url.trim()
      : "";
    if (!imageUrl) return jsonError("Missing required parameter: image_url");

    try {
      validateImageURL(imageUrl, Deno.env.get("SUPABASE_URL") ?? "");
    } catch {
      return jsonError("Invalid image URL");
    }
    const dataUrl = await fetchImageAsDataUrl(imageUrl);

    const ocrResult = await ocrExtractFromImage(dataUrl, body);
    const normalizedTask = await structureTask(ocrResult.text, context);

    return new Response(
      JSON.stringify({ success: true, task: normalizedTask }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    return jsonError("Image task recognition failed", 502);
  }
});
