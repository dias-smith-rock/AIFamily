// supabase/functions/send-huddle-flare/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const { tenant_id, sender_id, sender_name } = await req.json()

  // 1. 初始化 Supabase 服务端客户端
  const supabaseClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // 2. 查询该圈子内除了发送者以外的所有真实用户的 APNs Device Token
  // 假设你有一张存放设备 Token 的表 user_device_tokens
  const { data: tokens, error } = await supabaseClient
    .from('user_device_tokens')
    .select('apns_token')
    .eq('tenant_id', tenant_id)
    .not('user_id', 'eq', sender_id)

  if (error || !tokens || tokens.length === 0) {
    return new Response(JSON.stringify({ success: false, message: "No tokens found" }), { status: 200 })
  }

  // 3. 构建苹果 APNs 推送 Payload
  // 采用 "content-available": 1 实现静默唤醒 App 同步地图，同时带上 Alert 展现视觉信号弹
  const apnsPayload = {
    aps: {
      alert: {
        title: "📍 Live Location Flare!",
        body: `${sender_name} just launched a Live Huddle inside the venue. Tap to join!`,
      },
      sound: "default",
      "content-available": 1, // 关键：静默唤醒客户端，让 App 在后台立刻连接 Presence 刷新大盘
      category: "HUDDLE_JOIN_CATEGORY" // 可选：用于配置 iOS 通知快捷操作（如直接点击加入）
    },
    tenant_id: tenant_id
  }

  // 4. 循环调用 APNs HTTP/2 接口（此处简化为伪代码，实际开发中使用标准 APNs 证书/Token 鉴权发送）
  for (const item of tokens) {
    await sendToApns(item.apns_token, apnsPayload)
  }

  return new Response(JSON.stringify({ success: true }), { status: 200 })
})

async function sendToApns(token: string, payload: any) {
  // 实际开发中，在这里配置与苹果 APNs 的 HTTP/2 双向认证连接
  // 欧美服务器部署在 Supabase 边缘节点，延迟通常在 50ms 以内
}