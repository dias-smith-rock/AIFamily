import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

const TASK_JSON_SCHEMA_PROMPT = `You must reply with a valid JSON object matching this exact schema (use null for unknown fields, never omit keys):
{
  "title": "Short actionable task title in the image's primary language (max 50 chars)",
  "description": "Detailed notes: item lists, instructions, phone numbers, class names, or full context from the image",
  "due_date": "ISO8601 start datetime if a start/活动/集合/上课时间 is found, otherwise null",
  "end_datetime": "ISO8601 end/deadline datetime if 截止/结束/下课/到期 is found, otherwise null",
  "is_all_day": false,
  "duration_minutes": "integer minutes if a duration like '2小时' is stated without explicit end time, otherwise null",
  "amount_yuan": "number in major currency units (e.g. 128.5 for ¥128.50), otherwise null",
  "spatial_keywords": "Store/venue/school landmark for geofencing (e.g. 'Costco', '旺角东地铁站'), otherwise null",
  "location_address": "Full address string if visible, otherwise null",
  "participant_hints": ["Names or roles mentioned: e.g. '小明', '爸爸', '妈妈', '全班' — plain strings only, no UUIDs"],
  "priority": "low | normal | high | null",
  "task_type_hint": "scheduled | flexible | null (flexible for 待办/缴费截止 without fixed start time)"
}

Rules:
- Prefer concise title; put receipts line-items and notice body in description.
- Resolve relative dates (明天/下周三/this Friday) against the reference date provided by the user.
- If only a calendar day is visible without clock time, use 09:00 local implied time unless context suggests all-day.
- amount_yuan: parse ￥/¥/HK$/元/港币; ignore thousand separators; 128元 → 128.
- participant_hints: extract every person/role the task applies to; empty array if none.`

const SYSTEM_PROMPT = `You are an AI assistant for the family task app "WeSync".
Convert OCR text from photos (receipts, school notices, calendars, memos, bills, handwritten notes) into structured task JSON for creating a family task.
Current year context: 2026. Timezone assumption: Asia/Hong_Kong unless the image clearly states otherwise.

${TASK_JSON_SCHEMA_PROMPT}`

const DEFAULT_OCR_PROMPT = `Transcribe ALL legible text from this image accurately.
Preserve line breaks, numbers, dates, times, currency amounts, names, and addresses.
Output the raw transcription only — no commentary.
If the image is a calendar, transcribe the focused day cell and any adjacent context that helps interpret dates.
Correct obvious OCR confusions in Chinese handwriting when context is clear (e.g. 兴趣班, 缴费, 截止).`

function jsonError(message: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: message }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  })
}

type TextChatMessage = {
  role: "system" | "user" | "assistant"
  content: string
}

type MultimodalChatMessage = {
  role: "user"
  content: Array<{ type: "text"; text: string } | { type: "image_url"; image_url: { url: string } }>
}

type RecognitionRegion = {
  top_left?: { x?: number; y?: number }
  top_right?: { x?: number; y?: number }
  bottom_left?: { x?: number; y?: number }
  bottom_right?: { x?: number; y?: number }
}

type RequestBody = {
  image_url?: string
  target_date?: string
  recognition_region?: RecognitionRegion
}

function buildOcrUserPrompt(body: RequestBody): string {
  const parts: string[] = [DEFAULT_OCR_PROMPT]

  const targetDate = body.target_date?.trim()
  if (targetDate) {
    parts.push(
      `The user is creating a task for calendar day ${targetDate}. If this is a monthly calendar, focus on the cell for that day.`,
    )
  }

  const region = body.recognition_region
  if (region?.top_left && region?.top_right && region?.bottom_left && region?.bottom_right) {
    const fmt = (p: { x?: number; y?: number }) =>
      `(${(p.x ?? 0).toFixed(3)}, ${(p.y ?? 0).toFixed(3)})`
    parts.push(
      `Prioritize text inside the normalized image region with corners: `
        + `top-left ${fmt(region.top_left)}, top-right ${fmt(region.top_right)}, `
        + `bottom-left ${fmt(region.bottom_left)}, bottom-right ${fmt(region.bottom_right)} `
        + `(coordinates 0–1 relative to image width/height).`,
    )
  }

  return parts.join("\n\n")
}

function buildStructureUserPrompt(extractedText: string, body: RequestBody): string {
  const targetDate = body.target_date?.trim()
  const reference = targetDate
    ? `Reference calendar day from the app: ${targetDate}. Resolve relative dates against this day.`
    : "No reference day provided; infer dates from image context and assume year 2026 when the year is missing."

  return [
    "The following text was extracted from a user photo via OCR.",
    reference,
    "Produce the required structured family task JSON.",
    "",
    "--- OCR TEXT ---",
    extractedText,
    "--- END ---",
  ].join("\n")
}

async function callChatCompletions(args: {
  baseUrl: string
  apiKey: string
  model: string
  messages: Array<TextChatMessage | MultimodalChatMessage>
  jsonMode?: boolean
  label: string
}): Promise<string> {
  const isGoogleNative = args.baseUrl.includes("generativelanguage.googleapis.com")

  if (isGoogleNative) {
    const cleanModel = args.model.replace(/^models\//, "")
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${cleanModel}:generateContent`

    let promptText = DEFAULT_OCR_PROMPT
    let base64Data = ""
    let mimeType = "image/jpeg"

    const userMsg = args.messages.find((m) => m.role === "user")
    if (userMsg && Array.isArray(userMsg.content)) {
      for (const item of userMsg.content) {
        if (item.type === "text" && item.text) promptText = item.text
        if (item.type === "image_url" && item.image_url?.url) {
          const rawUrl = item.image_url.url
          if (rawUrl.startsWith("data:")) {
            const matches = rawUrl.match(/^data:([^;]+);base64,(.+)$/)
            if (matches) {
              mimeType = matches[1]
              base64Data = matches[2].replace(/\s/g, "")
            }
          }
        }
      }
    }

    const response = await fetch(url, {
      method: "POST",
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
    })

    const payload = await response.json().catch(() => null)
    if (!response.ok) {
      throw new Error(`${args.label} Google Native API ${response.status}: ${JSON.stringify(payload)}`)
    }

    const content = payload?.candidates?.[0]?.content?.parts?.[0]?.text
    if (!content?.trim()) {
      throw new Error(`${args.label} Google API 返回空。可能是 Free Tier 遭到节点高并发限制，请等 5 秒重试。`)
    }
    return content.trim()
  }

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
    const apiMessage = (payload as { error?: { message?: string } })?.error?.message ?? JSON.stringify(payload ?? {})
    throw new Error(`${args.label} API ${response.status}: ${apiMessage}`)
  }

  const content = (payload as { choices?: { message?: { content?: string } }[] })?.choices?.[0]?.message?.content
  if (!content?.trim()) throw new Error(`${args.label} returned empty content.`)
  return content.trim()
}

function resolveOcrConfig(): { baseUrl: string; apiKey: string; model: string } {
  const ocrKey = Deno.env.get("OCR_API_KEY")?.trim() || ""
  const baseUrl = "https://generativelanguage.googleapis.com"
  const model = Deno.env.get("OCR_MODEL")?.trim() || "gemini-2.5-flash"

  if (!ocrKey) {
    throw new Error("OCR 阶段的 Gemini API Key 未配置。请运行 supabase secrets set OCR_API_KEY=...")
  }

  return { baseUrl, apiKey: ocrKey, model }
}

function resolveDeepSeekTextConfig(): { baseUrl: string; apiKey: string; model: string } {
  const apiKey = Deno.env.get("DEEPSEEK_API_KEY")?.trim()
  if (!apiKey) {
    throw new Error("Server secret 'DEEPSEEK_API_KEY' is not configured.")
  }

  return {
    baseUrl: Deno.env.get("DEEPSEEK_API_BASE_URL")?.trim() || "https://api.deepseek.com/v1",
    apiKey,
    model: Deno.env.get("DEEPSEEK_TASK_MODEL")?.trim() || "deepseek-chat",
  }
}

type OcrExtractPayload = {
  stage: "ocr_extract"
  timestamp: string
  model: string
  provider_base_url: string
  char_count: number
  line_count: number
  lines: string[]
  text: string
}

function buildOcrExtractPayload(
  extractedText: string,
  ocr: { baseUrl: string; model: string },
): OcrExtractPayload {
  const lines = extractedText
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)

  return {
    stage: "ocr_extract",
    timestamp: new Date().toISOString(),
    model: ocr.model,
    provider_base_url: ocr.baseUrl,
    char_count: extractedText.length,
    line_count: lines.length,
    lines,
    text: extractedText,
  }
}

function logOcrExtractResult(payload: OcrExtractPayload): void {
  console.log("[parse-create-task-from-images] ocr_extract_result")
  console.log(JSON.stringify(payload, null, 2))
}

async function fetchImageAsDataUrl(imageUrl: string): Promise<string> {
  const res = await fetch(imageUrl)
  if (!res.ok) throw new Error(`Image fetch failed (HTTP ${res.status})`)
  const mime = res.headers.get("content-type")?.split(";")[0]?.trim() || "image/jpeg"
  const bytes = new Uint8Array(await res.arrayBuffer())
  let binary = ""
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return `data:${mime};base64,${btoa(binary)}`
}

async function ocrExtractFromImage(dataUrl: string, body: RequestBody): Promise<{
  text: string
  debug: OcrExtractPayload
}> {
  const ocr = resolveOcrConfig()
  const ocrPrompt = buildOcrUserPrompt(body)

  let extractedText = ""
  const maxRetries = 3
  let delay = 1000 // 初始等待 1 秒

  for (let i = 0; i < maxRetries; i++) {
    try {
      console.log(`[parse-create-task-from-images] Gemini Native Stage Attempt ${i + 1}/${maxRetries}`)

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
      })
      
      break // 🌟 成功拿到数据，立刻跳出循环
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error)
      // 🌟 如果判定为 Google 503 或者是免费层频控，触发指数退避等待
      if ((msg.includes("503") || msg.includes("UNAVAILABLE")) && i < maxRetries - 1) {
        console.warn(`[Gemini 503 Overload] Server busy. Retrying in ${delay}ms...`)
        await new Promise((resolve) => setTimeout(resolve, delay))
        delay *= 2 // 延迟翻倍：1s -> 2s -> 4s
      } else {
        throw error // 其他致命错误（如 401 或最后一次失败）直接抛出
      }
    }
  }

  const payload = buildOcrExtractPayload(extractedText, ocr)
  logOcrExtractResult(payload)
  return { text: extractedText, debug: payload }
}

type StructuredTask = Record<string, unknown>

function asTrimmedString(value: unknown, maxLen?: number): string | null {
  if (typeof value !== "string") return null
  const trimmed = value.trim()
  if (!trimmed) return null
  if (maxLen && trimmed.length > maxLen) return trimmed.slice(0, maxLen)
  return trimmed
}

function asNullableNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null
  const n = typeof value === "number" ? value : Number(String(value).replace(/,/g, ""))
  return Number.isFinite(n) ? n : null
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .filter((item) => item.length > 0)
}

function normalizeStructuredTask(raw: StructuredTask): StructuredTask {
  const title = asTrimmedString(raw.title, 50) ?? "New task"
  const description = asTrimmedString(raw.description)
  const spatialKeywords = asTrimmedString(raw.spatial_keywords)
  const locationAddress = asTrimmedString(raw.location_address)
  const participantHints = asStringArray(raw.participant_hints)

  let mergedDescription = description
  if (locationAddress) {
    mergedDescription = mergedDescription
      ? `${mergedDescription}\n\nAddr：${locationAddress}`
      : `Addr：${locationAddress}`
  }

  const amountYuan = asNullableNumber(raw.amount_yuan)
  const durationMinutes = asNullableNumber(raw.duration_minutes)
  const isAllDay = raw.is_all_day === true

  const priorityRaw = asTrimmedString(raw.priority)?.toLowerCase()
  const priority = priorityRaw === "low" || priorityRaw === "normal" || priorityRaw === "high"
    ? priorityRaw
    : null

  const taskTypeRaw = asTrimmedString(raw.task_type_hint)?.toLowerCase()
  const taskTypeHint = taskTypeRaw === "scheduled" || taskTypeRaw === "flexible" ? taskTypeRaw : null

  return {
    title,
    description: mergedDescription,
    due_date: asTrimmedString(raw.due_date),
    end_datetime: asTrimmedString(raw.end_datetime),
    is_all_day: isAllDay,
    duration_minutes: durationMinutes !== null ? Math.round(durationMinutes) : null,
    amount_yuan: amountYuan,
    spatial_keywords: spatialKeywords,
    participant_hints: participantHints,
    priority,
    task_type_hint: taskTypeHint,
  }
}

async function deepSeekStructureTask(extractedText: string, body: RequestBody): Promise<string> {
  const deepseek = resolveDeepSeekTextConfig()
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
        content: buildStructureUserPrompt(extractedText, body),
      },
    ],
  })
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  try {
    let body: RequestBody
    try {
      body = await req.json()
    } catch {
      return jsonError("Invalid JSON body")
    }

    const imageUrl = body.image_url?.trim()
    if (!imageUrl) return jsonError("Missing required parameter: image_url")

    const dataUrl = await fetchImageAsDataUrl(imageUrl)

    console.log(
      "[parse-create-task-from-images] pipeline=gemini_ocr+deepseek "
        + `target_date=${body.target_date ?? "nil"} region=${body.recognition_region ? "yes" : "no"}`,
    )
    const ocrResult = await ocrExtractFromImage(dataUrl, body)
    const rawJsonText = await deepSeekStructureTask(ocrResult.text, body)

    let structuredTask: StructuredTask
    try {
      structuredTask = JSON.parse(rawJsonText) as StructuredTask
    } catch {
      return jsonError(`Task JSON parse failed. Raw: ${rawJsonText.slice(0, 200)}`)
    }

    const normalizedTask = normalizeStructuredTask(structuredTask)

    return new Response(JSON.stringify({ success: true, task: normalizedTask, ocr_extract: ocrResult.debug }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error("[parse-create-task-from-images]", message)
    return jsonError(message)
  }
})
