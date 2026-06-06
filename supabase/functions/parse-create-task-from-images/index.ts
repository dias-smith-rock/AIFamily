import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

const TASK_JSON_SCHEMA_PROMPT = `You must reply with a valid JSON object matching this exact schema:
{
  "title": "Short actionable task title (max 50 chars)",
  "description": "Elaborated notes or item lists extracted from the image",
  "due_date": "ISO8601 string if a date/time is explicitly found, otherwise null",
  "spatial_keywords": "Any specific landmark/store name found (e.g., 'Costco', 'Target') for geofencing, otherwise null"
}`

const SYSTEM_PROMPT = `You are an AI assistant tailored for the family task sharing app "WeSync".
Analyze text extracted from a user photo (receipt, school notice, todo memo, handwritten note) and produce a structured family task.
Current year base context: 2026.

${TASK_JSON_SCHEMA_PROMPT}`

/** DeepSeek-OCR 官方推荐 prompt（见 DeepSeek-OCR-2 README） */
const OCR_USER_PROMPT = "<image>\nFree OCR."

function jsonError(message: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: message }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  })
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = ""
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}

async function fetchImageAsDataUrl(imageUrl: string): Promise<string> {
  const res = await fetch(imageUrl)
  if (!res.ok) {
    throw new Error(`Image fetch failed (HTTP ${res.status})`)
  }
  const mime = res.headers.get("content-type")?.split(";")[0]?.trim() || "image/jpeg"
  const bytes = new Uint8Array(await res.arrayBuffer())
  return `data:${mime};base64,${bytesToBase64(bytes)}`
}

type TextChatMessage = {
  role: "system" | "user" | "assistant"
  content: string
}

type MultimodalChatMessage = {
  role: "user"
  content: Array<{ type: "text"; text: string } | { type: "image_url"; image_url: { url: string } }>
}

async function callChatCompletions(args: {
  baseUrl: string
  apiKey: string
  model: string
  messages: Array<TextChatMessage | MultimodalChatMessage>
  jsonMode?: boolean
  label: string
}): Promise<string> {
  const url = `${args.baseUrl.replace(/\/$/, "")}/chat/completions`
  const response = await fetch(url, {
    method: "POST",
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
  })

  const payload = await response.json().catch(() => null)

  if (!response.ok) {
    const apiMessage =
      (payload as { error?: { message?: string } })?.error?.message ??
      JSON.stringify(payload ?? {}).slice(0, 400)

    if (response.status === 401 && args.label === "OCR-Stage1") {
      throw new Error(
        `${args.label} API 401: API Key 对当前 OCR 端点无效。` +
          ` platform.deepseek.com 的 Key 只能用于阶段2（api.deepseek.com 文本模型），` +
          `不能用于阶段1 OCR。请在 Supabase Secrets 单独配置 SILICONFLOW_API_KEY（硅基流动），` +
          `或指向自建 OCR 代理的 OCR_API_BASE_URL + OCR_API_KEY。` +
          ` 当前端点: ${args.baseUrl} | 上游: ${apiMessage}`,
      )
    }

    throw new Error(`${args.label} API ${response.status}: ${apiMessage}`)
  }

  const content = (payload as { choices?: { message?: { content?: string } }[] })
    ?.choices?.[0]?.message?.content

  if (!content?.trim()) {
    throw new Error(`${args.label} returned empty content: ${JSON.stringify(payload).slice(0, 300)}`)
  }

  return content.trim()
}

/** 阶段 1 OCR：必须使用支持 image_url 的 OCR 端点（非 api.deepseek.com 文本 API）。
 *
 * Supabase Secrets 示例（两套 Key，不可混用）：
 * - DEEPSEEK_API_KEY=sk-...           → 阶段2，api.deepseek.com
 * - SILICONFLOW_API_KEY=sk-...        → 阶段1，api.siliconflow.cn
 * - OCR_MODEL=deepseek-ai/DeepSeek-OCR
 *
 * platform.deepseek.com 创建的 Key（如 WeSync-create-task-from-image）
 * 只能填入 DEEPSEEK_API_KEY，不能填入 OCR_API_KEY / SILICONFLOW_API_KEY。
 */
function resolveOcrConfig(): { baseUrl: string; apiKey: string; model: string } {
  const siliconflowKey = Deno.env.get("SILICONFLOW_API_KEY")?.trim() || ""
  const ocrKey = Deno.env.get("OCR_API_KEY")?.trim() || ""
  const deepseekKey = Deno.env.get("DEEPSEEK_API_KEY")?.trim() || ""

  // 优先专用 OCR Key；勿把 DEEPSEEK_API_KEY 当作 OCR Key 回退（会在第三方端点 401）
  const apiKey = ocrKey || siliconflowKey

  const baseUrl =
    Deno.env.get("OCR_API_BASE_URL")?.trim() ||
    (siliconflowKey || ocrKey ? inferOcrBaseUrl(ocrKey, siliconflowKey) : "")

  const model =
    Deno.env.get("OCR_MODEL")?.trim() ||
    Deno.env.get("VISION_MODEL")?.trim() ||
    "deepseek-ai/DeepSeek-OCR"

  if (!apiKey || !baseUrl) {
    throw new Error(
      "OCR 阶段未配置。DeepSeek 开放平台 Key 无法用于 OCR（官方 API 不支持识图）。" +
        "请注册硅基流动 https://siliconflow.cn 获取 SILICONFLOW_API_KEY，" +
        "或配置 OCR_API_BASE_URL + OCR_API_KEY 指向你的 Deepseek-OCR2 代理。",
    )
  }

  if (deepseekKey && apiKey === deepseekKey && !baseUrl.includes("api.deepseek.com")) {
    throw new Error(
      "OCR_API_KEY / SILICONFLOW_API_KEY 与 DEEPSEEK_API_KEY 相同，但 OCR 端点不是 api.deepseek.com。" +
        "请为阶段1单独申请 SILICONFLOW_API_KEY；DeepSeek 开放平台 Key 仅用于 DEEPSEEK_API_KEY（阶段2）。",
    )
  }

  if (baseUrl.includes("api.deepseek.com")) {
    throw new Error(
      "OCR 阶段不能使用 api.deepseek.com（仅支持纯文本）。" +
        "请改用 SILICONFLOW_API_KEY 或自建 OCR 代理。",
    )
  }

  return { baseUrl, apiKey, model }
}

function inferOcrBaseUrl(ocrKey: string, siliconflowKey: string): string {
  if (siliconflowKey) {
    return "https://api.siliconflow.cn/v1"
  }
  // 显式 OCR_API_KEY 但未设 BASE_URL 时，默认硅基（最常见）
  if (ocrKey) {
    return "https://api.siliconflow.cn/v1"
  }
  return ""
}

/** 阶段 2：DeepSeek 纯文本模型结构化 JSON。 */
function resolveDeepSeekTextConfig(): { baseUrl: string; apiKey: string; model: string } {
  const apiKey = Deno.env.get("DEEPSEEK_API_KEY")?.trim()
  if (!apiKey) {
    throw new Error("Server secret 'DEEPSEEK_API_KEY' is not configured.")
  }

  return {
    baseUrl: Deno.env.get("DEEPSEEK_API_BASE_URL")?.trim() || "https://api.deepseek.com/v1",
    apiKey,
    model:
      Deno.env.get("DEEPSEEK_TASK_MODEL")?.trim() ||
      Deno.env.get("DEEPSEEK_STRUCTURE_MODEL")?.trim() ||
      "deepseek-chat",
  }
}

async function ocrExtractFromImage(dataUrl: string): Promise<string> {
  const ocr = resolveOcrConfig()
  console.log(
    `[parse-create-task-from-images] OCR stage base=${ocr.baseUrl} model=${ocr.model}`,
  )

  return await callChatCompletions({
    baseUrl: ocr.baseUrl,
    apiKey: ocr.apiKey,
    model: ocr.model,
    label: "OCR-Stage1",
    messages: [
      {
        role: "user",
        content: [
          { type: "image_url", image_url: { url: dataUrl } },
          { type: "text", text: OCR_USER_PROMPT },
        ],
      },
    ],
  })
}

async function deepSeekStructureTask(extractedText: string): Promise<string> {
  const deepseek = resolveDeepSeekTextConfig()
  console.log(
    `[parse-create-task-from-images] Structure stage base=${deepseek.baseUrl} model=${deepseek.model}`,
  )

  return await callChatCompletions({
    baseUrl: deepseek.baseUrl,
    apiKey: deepseek.apiKey,
    model: deepseek.model,
    label: "DeepSeek-Stage2",
    jsonMode: true,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      {
        role: "user",
        content:
          `The following text was extracted from a user photo via OCR. ` +
          `Turn it into the JSON task schema.\n\n---\n${extractedText}\n---`,
      },
    ],
  })
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    let body: { image_url?: string }
    try {
      body = await req.json()
    } catch {
      return jsonError("Invalid JSON body")
    }

    const imageUrl = body.image_url?.trim()
    if (!imageUrl) {
      return jsonError("Missing required parameter: image_url")
    }

    const dataUrl = await fetchImageAsDataUrl(imageUrl)

    console.log("[parse-create-task-from-images] pipeline=ocr_then_deepseek")
    const extractedText = await ocrExtractFromImage(dataUrl)
    const rawJsonText = await deepSeekStructureTask(extractedText)

    let structuredTask: unknown
    try {
      structuredTask = JSON.parse(rawJsonText)
    } catch {
      return jsonError(`Task JSON parse failed. Raw: ${rawJsonText.slice(0, 200)}`)
    }

    return new Response(JSON.stringify({ success: true, task: structuredTask }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error("[parse-create-task-from-images]", message)
    return jsonError(message)
  }
})
