import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // 拦截浏览器的预检请求 (CORS)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. 接收从 iOS 客户端传过来的、存放在 create-task-from-images 桶中的图片公网 URL
    const { image_url } = await req.json()
    if (!image_url) {
      throw new Error("Missing required parameter: image_url")
    }

    const apiKey = Deno.env.get('DEEPSEEK_API_KEY')
    if (!apiKey) {
      throw new Error("Server secret 'DEEPSEEK_API_KEY' is not configured.")
    }

    // 2. 发起面向 DeepSeek 多模态模型的结构化请求（2026年基准时间轴）
    const response = await fetch('https://api.deepseek.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      body: JSON.stringify({
        model: "deepseek-vl", 
        response_format: { type: "json_object" }, // 强力约束纯净 JSON 输出
        messages: [
          {
            role: "system",
            content: `You are an AI assistant tailored for the family task sharing app "WeSync".
Analyze the user's uploaded image (receipt, school notice, todo memo, handwritten note) and extract a structured family task.
Current year base context: 2026.

You must reply with a valid JSON object matching this exact schema:
{
  "title": "Short actionable task title (max 50 chars)",
  "description": "Elaborated notes or item lists extracted from the image",
  "due_date": "ISO8601 string if a date/time is explicitly found, otherwise null",
  "spatial_keywords": "Any specific landmark/store name found (e.g., 'Costco', 'Target') for geofencing, otherwise null"
}`
          },
          {
            role: "user",
            content: [
              {
                type: "text",
                text: "Please extract the task items from this image following the system json template."
              },
              {
                type: "image_url",
                image_url: {
                  url: image_url
                }
              }
            ]
          }
        ],
        temperature: 0.1
      })
    })

    const aiResult = await response.json()
    const rawJsonText = aiResult.choices[0].message.content
    const structuredTask = JSON.parse(rawJsonText)

    return new Response(JSON.stringify({ success: true, task: structuredTask }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200
    })

  } catch (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400
    })
  }
})