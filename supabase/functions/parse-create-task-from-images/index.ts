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

const OCR_USER_PROMPT = "Look at this school/family calendar image. Locate the grid box belonging to day '12' (which also has the printed lunar date '廿七'). Read the handwritten text inside that specific grid box very carefully. Transcribe the handwritten blue/black ink words into clear, standard Chinese characters. Do not get confused by the handwriting strokes; understand the context of school and classes (like '兴趣班', '最后一天', '全日制上课'). Output only the extracted text from day 12, do not chat."

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
    
    // 🌟 终极安全升级：URL 保持绝对干净，不带任何问号或特殊转义字符
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${cleanModel}:generateContent`
    
    let promptText = OCR_USER_PROMPT
    let base64Data = ""
    let mimeType = "image/jpeg"

    const userMsg = args.messages.find(m => m.role === "user")
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
      // 🌟 核心破局：利用官方标准的 x-goog-api-key 报头暗送密钥，安全防拦截
      headers: { 
        "Content-Type": "application/json",
        "x-goog-api-key": args.apiKey
      },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              { text: promptText },
              { inlineData: { mimeType: mimeType, data: base64Data } }
            ]
          }
        ],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 1024
        }
      })
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

  } else {
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

async function ocrExtractFromImage(dataUrl: string): Promise<{
  text: string
  debug: OcrExtractPayload
}> {
  const ocr = resolveOcrConfig()
  console.log(`[parse-create-task-from-images] Launching Gemini Native Header Stage model=${ocr.model}`)

  const extractedText = await callChatCompletions({
    baseUrl: ocr.baseUrl,
    apiKey: ocr.apiKey,
    model: ocr.model,
    label: "OCR-Stage1-GeminiNative",
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

  const payload = buildOcrExtractPayload(extractedText, ocr)
  logOcrExtractResult(payload)
  return { text: extractedText, debug: payload }
}

async function deepSeekStructureTask(extractedText: string): Promise<string> {
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
        content: `The following text was extracted from a calendar photo via Gemini. Turn it into our required structured family task JSON schema.\n\n---\n${extractedText}\n---`,
      },
    ],
  })
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  try {
    let body: { image_url?: string }
    try {
      body = await req.json()
    } catch {
      return jsonError("Invalid JSON body")
    }

    const imageUrl = body.image_url?.trim()
    if (!imageUrl) return jsonError("Missing required parameter: image_url")

    const dataUrl = await fetchImageAsDataUrl(imageUrl)

    console.log("[parse-create-task-from-images] running pipeline: gemini_header_then_deepseek")
    const ocrResult = await ocrExtractFromImage(dataUrl)
    const rawJsonText = await deepSeekStructureTask(ocrResult.text)

    let structuredTask: unknown
    try {
      structuredTask = JSON.parse(rawJsonText)
    } catch {
      return jsonError(`Task JSON parse failed. Raw: ${rawJsonText.slice(0, 200)}`)
    }

    return new Response(JSON.stringify({ success: true, task: structuredTask, ocr_extract: ocrResult.debug }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error("[parse-create-task-from-images]", message)
    return jsonError(message)
  }
})