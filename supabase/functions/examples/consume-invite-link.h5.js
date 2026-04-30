/**
 * H5 调用示例：consume-invite-link
 * 错误码映射：
 * - 409: 已消费
 * - 410: 已过期
 */
export async function consumeInviteLink({
  supabaseProjectUrl,
  anonKey,
  sig,
}) {
  if (!sig) {
    throw new Error("缺少 sig 参数");
  }

  const endpoint = `${supabaseProjectUrl.replace(/\/$/, "")}/functions/v1/consume-invite-link`;
  const resp = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
    },
    body: JSON.stringify({ sig }),
  });

  const text = await resp.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = { raw: text };
  }

  if (resp.status === 200) {
    return {
      ok: true,
      data: body,
      reason: null,
    };
  }

  if (resp.status === 409) {
    return {
      ok: false,
      data: null,
      reason: "already_consumed",
      message: "邀请链接已被使用，请让家长重新生成。",
    };
  }

  if (resp.status === 410) {
    return {
      ok: false,
      data: null,
      reason: "expired",
      message: "邀请链接已过期，请让家长重新生成。",
    };
  }

  if (resp.status === 400 || resp.status === 404) {
    return {
      ok: false,
      data: null,
      reason: "invalid_or_tampered",
      message: "邀请链接无效或被篡改。",
    };
  }

  if (resp.status === 401) {
    return {
      ok: false,
      data: null,
      reason: "unauthorized",
      message: "鉴权失败，请检查 apikey 配置。",
    };
  }

  return {
    ok: false,
    data: null,
    reason: "unknown",
    message: body?.error ?? "未知错误",
  };
}

/**
 * 页面中从 URL 读取 sig 的示例
 */
export function getSigFromURL() {
  const params = new URLSearchParams(window.location.search);
  return params.get("sig");
}
