import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import jpeg from "jpeg-js"

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

const DEFAULT_OCR_USER_PROMPT = "<image>\nFree OCR."

const RED_BOX_OCR_USER_PROMPT =
  "<image>\nFree OCR. This image shows only the user-selected region from a photo. " +
  "Extract all readable text in the image."

const FALLBACK_OCR_PROMPTS = [
  "<image>\nFree OCR.",
  "<image>\n<|grounding|>OCR this image.",
]

const MAX_OCR_CHARS = 2000
const MAX_OCR_LINES = 80
const LUNAR_RUN_THRESHOLD = 15

/** 农历单行标签（用于检测 OCR 幻觉循环） */
const LUNAR_LINE_PATTERN =
  /^(初[一二三四五六七八九十]{1,2}|廿[一二三四五六七八九十]?|三十|三十一)$/

function resolveOcrUserPrompt(): string {
  return Deno.env.get("OCR_USER_PROMPT")?.trim() || DEFAULT_OCR_USER_PROMPT
}

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

type NormalizedPoint = { x: number; y: number }

type RecognitionRegion = {
  top_left: NormalizedPoint
  top_right: NormalizedPoint
  bottom_left: NormalizedPoint
  bottom_right: NormalizedPoint
}

async function fetchImageBytes(imageUrl: string): Promise<{ bytes: Uint8Array; mime: string }> {
  const res = await fetch(imageUrl)
  if (!res.ok) {
    throw new Error(`Image fetch failed (HTTP ${res.status})`)
  }
  const mime = res.headers.get("content-type")?.split(";")[0]?.trim() || "image/jpeg"
  const bytes = new Uint8Array(await res.arrayBuffer())
  return { bytes, mime }
}

function bytesToDataUrl(bytes: Uint8Array, mime: string): string {
  return `data:${mime};base64,${bytesToBase64(bytes)}`
}

function parseRecognitionRegion(raw: unknown): RecognitionRegion | null {
  if (!raw || typeof raw !== "object") return null

  const region = raw as Record<string, unknown>
  const parsePoint = (key: string): NormalizedPoint | null => {
    const value = region[key]
    if (!value || typeof value !== "object") return null
    const point = value as Record<string, unknown>
    const x = Number(point.x)
    const y = Number(point.y)
    if (!Number.isFinite(x) || !Number.isFinite(y)) return null
    if (x < 0 || x > 1 || y < 0 || y > 1) return null
    return { x, y }
  }

  const topLeft = parsePoint("top_left")
  const topRight = parsePoint("top_right")
  const bottomLeft = parsePoint("bottom_left")
  const bottomRight = parsePoint("bottom_right")
  if (!topLeft || !topRight || !bottomLeft || !bottomRight) return null

  const area = polygonArea(topLeft, topRight, bottomRight, bottomLeft)
  if (area < 0.01) return null

  return {
    top_left: topLeft,
    top_right: topRight,
    bottom_left: bottomLeft,
    bottom_right: bottomRight,
  }
}

function polygonArea(
  a: NormalizedPoint,
  b: NormalizedPoint,
  c: NormalizedPoint,
  d: NormalizedPoint,
): number {
  return Math.abs(
    (a.x * b.y - b.x * a.y) +
      (b.x * c.y - c.x * b.y) +
      (c.x * d.y - d.x * c.y) +
      (d.x * a.y - a.x * d.y),
  ) / 2
}

function toPixelPoint(point: NormalizedPoint, width: number, height: number): { x: number; y: number } {
  return {
    x: Math.min(width - 1, Math.max(0, Math.round(point.x * (width - 1)))),
    y: Math.min(height - 1, Math.max(0, Math.round(point.y * (height - 1)))),
  }
}

const MIN_REGION_CROP_PIXEL = 640

/** 从上传的原图 JPEG 按红框外接矩形裁切（服务端裁切，避免客户端压缩后不可读）。 */
function cropRecognitionRegionJpeg(
  imageBytes: Uint8Array,
  region: RecognitionRegion,
): Uint8Array {
  const decoded = jpeg.decode(imageBytes, { useTArray: true })
  const width = decoded.width
  const height = decoded.height
  if (width <= 0 || height <= 0) {
    throw new Error("Failed to decode JPEG for recognition region")
  }

  const corners = [
    toPixelPoint(region.top_left, width, height),
    toPixelPoint(region.top_right, width, height),
    toPixelPoint(region.bottom_left, width, height),
    toPixelPoint(region.bottom_right, width, height),
  ]

  let x0 = Math.min(...corners.map((point) => point.x))
  let y0 = Math.min(...corners.map((point) => point.y))
  let x1 = Math.max(...corners.map((point) => point.x))
  let y1 = Math.max(...corners.map((point) => point.y))

  let cropWidth = Math.max(1, x1 - x0 + 1)
  let cropHeight = Math.max(1, y1 - y0 + 1)

  const shortest = Math.min(cropWidth, cropHeight)
  if (shortest < MIN_REGION_CROP_PIXEL && shortest > 0) {
    const scale = MIN_REGION_CROP_PIXEL / shortest
    const centerX = (x0 + x1) / 2
    const centerY = (y0 + y1) / 2
    cropWidth = Math.min(width, Math.round(cropWidth * scale))
    cropHeight = Math.min(height, Math.round(cropHeight * scale))
    x0 = Math.max(0, Math.round(centerX - (cropWidth - 1) / 2))
    y0 = Math.max(0, Math.round(centerY - (cropHeight - 1) / 2))
    x1 = Math.min(width - 1, x0 + cropWidth - 1)
    y1 = Math.min(height - 1, y0 + cropHeight - 1)
    cropWidth = x1 - x0 + 1
    cropHeight = y1 - y0 + 1
  }

  const cropped = new Uint8Array(cropWidth * cropHeight * 4)
  for (let y = 0; y < cropHeight; y++) {
    for (let x = 0; x < cropWidth; x++) {
      const srcIndex = ((y0 + y) * width + (x0 + x)) * 4
      const dstIndex = (y * cropWidth + x) * 4
      cropped[dstIndex] = decoded.data[srcIndex]
      cropped[dstIndex + 1] = decoded.data[srcIndex + 1]
      cropped[dstIndex + 2] = decoded.data[srcIndex + 2]
      cropped[dstIndex + 3] = decoded.data[srcIndex + 3]
    }
  }

  const encoded = jpeg.encode(
    { data: cropped, width: cropWidth, height: cropHeight },
    92,
  )
  return encoded.data
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
  maxTokens?: number
  allowEmpty?: boolean
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
      ...(args.maxTokens ? { max_tokens: args.maxTokens } : {}),
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
    if (args.allowEmpty) {
      console.log(
        `[parse-create-task-from-images] ${args.label} empty content: ${
          JSON.stringify(payload).slice(0, 300)
        }`,
      )
      return ""
    }
    throw new Error(`${args.label} returned empty content: ${JSON.stringify(payload).slice(0, 300)}`)
  }

  return content.trim()
}

async function runOcrWithPrompt(args: {
  dataUrl: string
  ocr: { baseUrl: string; apiKey: string; model: string }
  prompt: string
}): Promise<string> {
  return await callChatCompletions({
    baseUrl: args.ocr.baseUrl,
    apiKey: args.ocr.apiKey,
    model: args.ocr.model,
    label: "OCR-Stage1",
    maxTokens: 4096,
    allowEmpty: true,
    messages: [
      {
        role: "user",
        content: [
          { type: "image_url", image_url: { url: args.dataUrl } },
          { type: "text", text: args.prompt },
        ],
      },
    ],
  })
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

type OcrExtractPayload = {
  stage: "ocr_extract"
  timestamp: string
  model: string
  provider_base_url: string
  char_count: number
  line_count: number
  lines: string[]
  text: string
  raw_text?: string
  raw_char_count?: number
  sanitized?: boolean
  crop_hint?: string
  recognition_region?: RecognitionRegion
  target_date?: string
}

type SanitizeOcrResult = {
  text: string
  rawText: string
  sanitized: boolean
}

function isLunarCalendarLine(line: string): boolean {
  return LUNAR_LINE_PATTERN.test(line.trim())
}

function sanitizeOcrText(rawText: string): SanitizeOcrResult {
  const raw = rawText.trim()
  let lines = raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)

  let lunarRun = 0
  let truncateAt: number | null = null
  for (let i = 0; i < lines.length; i++) {
    if (isLunarCalendarLine(lines[i])) {
      lunarRun++
      if (lunarRun >= LUNAR_RUN_THRESHOLD) {
        truncateAt = i - LUNAR_RUN_THRESHOLD + 1
        break
      }
    } else {
      lunarRun = 0
    }
  }

  if (truncateAt !== null && truncateAt >= 0) {
    console.log(
      `[parse-create-task-from-images] ocr_hallucination_truncated at_line=${truncateAt}`,
    )
    lines = lines.slice(0, truncateAt)
  }

  if (lines.length > MAX_OCR_LINES) {
    console.log(
      `[parse-create-task-from-images] ocr_max_lines_truncated before=${lines.length} after=${MAX_OCR_LINES}`,
    )
    lines = lines.slice(0, MAX_OCR_LINES)
  }

  let text = lines.join("\n")
  if (text.length > MAX_OCR_CHARS) {
    console.log(
      `[parse-create-task-from-images] ocr_max_chars_truncated before=${text.length} after=${MAX_OCR_CHARS}`,
    )
    text = text.slice(0, MAX_OCR_CHARS)
  }

  return {
    text,
    rawText: raw,
    sanitized: text !== raw,
  }
}

function buildOcrExtractPayload(
  sanitized: SanitizeOcrResult,
  ocr: { baseUrl: string; model: string },
  meta?: { targetDate?: string; recognitionRegion?: RecognitionRegion },
): OcrExtractPayload {
  const lines = sanitized.text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)

  return {
    stage: "ocr_extract",
    timestamp: new Date().toISOString(),
    model: ocr.model,
    provider_base_url: ocr.baseUrl,
    char_count: sanitized.text.length,
    line_count: lines.length,
    lines,
    text: sanitized.text,
    raw_text: sanitized.rawText,
    raw_char_count: sanitized.rawText.length,
    sanitized: sanitized.sanitized,
    crop_hint: meta?.recognitionRegion ? "client_red_box_region_server_crop" : "full_image",
    ...(meta?.recognitionRegion ? { recognition_region: meta.recognitionRegion } : {}),
    ...(meta?.targetDate ? { target_date: meta.targetDate } : {}),
  }
}

function logOcrExtractResult(payload: OcrExtractPayload): void {
  console.log("[parse-create-task-from-images] ocr_extract_result")
  console.log(JSON.stringify(payload, null, 2))
}

function shouldIncludeOcrInResponse(): boolean {
  return Deno.env.get("AI_TASK_INCLUDE_OCR_DEBUG")?.trim() !== "false"
}

async function ocrExtractFromImage(
  dataUrl: string,
  targetDate?: string,
  options?: { recognitionRegion?: RecognitionRegion },
): Promise<{
  text: string
  debug: OcrExtractPayload
}> {
  const ocr = resolveOcrConfig()
  console.log(
    `[parse-create-task-from-images] OCR stage base=${ocr.baseUrl} model=${ocr.model} target_date=${targetDate ?? "none"} red_box=${options?.recognitionRegion ? "yes" : "no"}`,
  )

  const promptCandidates = (
    options?.recognitionRegion
      ? [RED_BOX_OCR_USER_PROMPT, resolveOcrUserPrompt(), ...FALLBACK_OCR_PROMPTS]
      : [resolveOcrUserPrompt(), ...FALLBACK_OCR_PROMPTS]
  ).filter((prompt, index, all) => all.indexOf(prompt) === index)

  let rawExtractedText = ""
  let usedPrompt = promptCandidates[0]
  for (const prompt of promptCandidates) {
    usedPrompt = prompt
    const attempt = await runOcrWithPrompt({ dataUrl, ocr, prompt })
    if (attempt.trim()) {
      rawExtractedText = attempt
      console.log(
        `[parse-create-task-from-images] ocr_prompt_ok chars=${attempt.length} prompt=${
          prompt.replace(/\n/g, "\\n").slice(0, 60)
        }`,
      )
      break
    }
    console.log(
      `[parse-create-task-from-images] ocr_empty_retry prompt=${prompt.replace(/\n/g, "\\n").slice(0, 60)}`,
    )
  }

  if (!rawExtractedText.trim()) {
    throw new Error(
      options?.recognitionRegion
        ? "OCR-Stage1 returned empty content after trying all prompts. " +
          "The red box region may be too small or unreadable; try enlarging the selection."
        : "OCR-Stage1 returned empty content after trying all prompts. " +
          "The image may be too small or unreadable; try retaking the photo.",
    )
  }

  const sanitized = sanitizeOcrText(rawExtractedText)
  if (sanitized.sanitized) {
    console.log(
      `[parse-create-task-from-images] ocr_sanitize raw_chars=${sanitized.rawText.length} clean_chars=${sanitized.text.length}`,
    )
  }

  const payload = buildOcrExtractPayload(sanitized, ocr, {
    targetDate,
    recognitionRegion: options?.recognitionRegion,
  })
  payload.crop_hint = `${payload.crop_hint}|prompt=${usedPrompt.replace(/\n/g, " ").slice(0, 40)}`
  logOcrExtractResult(payload)
  return { text: sanitized.text, debug: payload }
}

async function deepSeekStructureTask(
  extractedText: string,
  targetDate?: string,
): Promise<string> {
  const deepseek = resolveDeepSeekTextConfig()
  console.log(
    `[parse-create-task-from-images] Structure stage base=${deepseek.baseUrl} model=${deepseek.model} target_date=${targetDate ?? "none"}`,
  )

  let userContent =
    `The following text was extracted from a user photo via OCR. ` +
    `Turn it into the JSON task schema.\n\n---\n${extractedText}\n---`

  if (targetDate) {
    userContent +=
      `\n\nTarget calendar date: ${targetDate}. Extract ONLY tasks/events for this date from the OCR text.` +
      `\nIgnore printed lunar labels (初一/廿七) unless part of an event description.` +
      `\nCurrent year: 2026. Infer month from OCR context if present (e.g. 6月).`
  }

  return await callChatCompletions({
    baseUrl: deepseek.baseUrl,
    apiKey: deepseek.apiKey,
    model: deepseek.model,
    label: "DeepSeek-Stage2",
    jsonMode: true,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: userContent },
    ],
  })
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    let body: {
      image_url?: string
      target_date?: string
      recognition_region?: unknown
    }
    try {
      body = await req.json()
    } catch {
      return jsonError("Invalid JSON body")
    }

    const imageUrl = body.image_url?.trim()
    if (!imageUrl) {
      return jsonError("Missing required parameter: image_url")
    }

    const targetDate = body.target_date?.trim() || undefined
    const recognitionRegion = body.recognition_region
      ? parseRecognitionRegion(body.recognition_region)
      : null

    if (body.recognition_region && !recognitionRegion) {
      return jsonError("Invalid recognition_region")
    }

    const { bytes, mime } = await fetchImageBytes(imageUrl)
    let ocrBytes = bytes
    let ocrMime = mime
    if (recognitionRegion) {
      try {
        ocrBytes = cropRecognitionRegionJpeg(bytes, recognitionRegion)
        ocrMime = "image/jpeg"
        console.log(
          `[parse-create-task-from-images] region_cropped bytes=${ocrBytes.length} region=${
            JSON.stringify(recognitionRegion)
          }`,
        )
      } catch (cropError) {
        const cropMessage = cropError instanceof Error ? cropError.message : String(cropError)
        console.error(`[parse-create-task-from-images] region_crop_failed ${cropMessage}`)
        throw new Error(`Recognition region crop failed: ${cropMessage}`)
      }
    }

    const dataUrl = bytesToDataUrl(ocrBytes, ocrMime)

    console.log(
      `[parse-create-task-from-images] pipeline=ocr_then_deepseek mode=${
        recognitionRegion ? "red_box_server_crop" : "full_image"
      } target_date=${targetDate ?? "none"}`,
    )
    const ocrResult = await ocrExtractFromImage(dataUrl, targetDate, {
      recognitionRegion: recognitionRegion ?? undefined,
    })
    const rawJsonText = await deepSeekStructureTask(ocrResult.text, targetDate)

    let structuredTask: unknown
    try {
      structuredTask = JSON.parse(rawJsonText)
    } catch {
      return jsonError(`Task JSON parse failed. Raw: ${rawJsonText.slice(0, 200)}`)
    }

    const responseBody: Record<string, unknown> = {
      success: true,
      task: structuredTask,
    }

    if (shouldIncludeOcrInResponse()) {
      responseBody.ocr_extract = ocrResult.debug
    }

    return new Response(JSON.stringify(responseBody), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error("[parse-create-task-from-images]", message)
    return jsonError(message, 500)
  }
})
