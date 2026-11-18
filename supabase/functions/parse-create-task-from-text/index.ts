import {
  allowRequest,
  authenticatedUser,
  corsHeaders,
  jsonResponse,
  parsingContext,
  structureTask,
  validateText,
} from "../_shared/task-parsing.ts";

export async function handleTextRequest(
  req: Request,
  dependencies = { authenticatedUser, structureTask },
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }
  try {
    const userId = await dependencies.authenticatedUser(req);
    if (!userId) {
      return jsonResponse({ success: false, error: "Unauthorized" }, 401);
    }
    if (!allowRequest(userId)) {
      return jsonResponse({ success: false, error: "Too many requests" }, 429);
    }
    let text: string, context: string;
    try {
      if (Number(req.headers.get("content-length")) > 40000) {
        throw new Error("Request too large");
      }
      const raw = await req.text();
      if (raw.length > 40000) throw new Error("Request too large");
      const body = JSON.parse(raw);
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        throw new Error("Invalid body");
      }
      text = validateText(body.text);
      context = parsingContext(body, true);
    } catch {
      return jsonResponse({
        success: false,
        error: "Invalid text or parsing context (maximum 6000 characters)",
      }, 400);
    }
    return jsonResponse({
      success: true,
      task: await dependencies.structureTask(text, context),
    });
  } catch {
    return jsonResponse({
      success: false,
      error: "Task recognition unavailable. Please retry.",
    }, 502);
  }
}
if (import.meta.main) Deno.serve((req) => handleTextRequest(req));
