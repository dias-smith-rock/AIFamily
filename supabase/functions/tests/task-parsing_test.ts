import {
  authenticatedUser,
  normalizeStructuredTask,
  parsingContext,
  structureTask,
  validateImageURL,
  validateText,
} from "../_shared/task-parsing.ts";
import { handleTextRequest } from "../parse-create-task-from-text/index.ts";
function assert(value: unknown): asserts value {
  if (!value) throw new Error("Assertion failed");
}
function rejects(fn: () => unknown) {
  let threw = false;
  try {
    fn();
  } catch {
    threw = true;
  }
  assert(threw);
}
const context = {
  reference_instant: "2027-12-31T23:00:00Z",
  selected_calendar_day: "2027-11-01",
  time_zone: "America/Los_Angeles",
  locale: "en-US",
};
Deno.test("text input rejects blank and 6001 characters, accepts 6000 Unicode characters", () => {
  rejects(() => validateText(" "));
  rejects(() => validateText("a".repeat(6001)));
  assert(Array.from(validateText("😀".repeat(6000))).length === 6000);
});
Deno.test("explicit context anchors reference instant, legacy uses current year", () => {
  const prompt = parsingContext(context, true);
  assert(
    prompt.includes(context.reference_instant) &&
      prompt.includes(context.time_zone) &&
      prompt.includes("NOT the relative-date anchor"),
  );
  assert(
    parsingContext(
      { target_date: "2030-01-01" },
      false,
      new Date("2031-01-01Z"),
    ).includes("2031-01-01"),
  );
  rejects(() => parsingContext({ ...context, time_zone: "bad/zone" }, true));
  rejects(() =>
    parsingContext({ ...context, reference_instant: "tomorrow" }, true)
  );
  rejects(() =>
    parsingContext({ ...context, selected_calendar_day: "2027-02-30" }, true)
  );
});
Deno.test("normalized payload preserves unknown times and rejects invalid business fields", () => {
  const task = normalizeStructuredTask({
    title: " Buy milk ",
    participant_hints: ["Dad"],
    due_date: null,
  });
  assert(
    task.title === "Buy milk" && task.due_date === null &&
      task.end_datetime === null,
  );
  rejects(() => normalizeStructuredTask({ title: "x", duration_minutes: -2 }));
  rejects(() => normalizeStructuredTask({ title: "x", due_date: "tomorrow" }));
  rejects(() =>
    normalizeStructuredTask({
      title: "x",
      due_date: "2027-01-02T12:00:00Z",
      end_datetime: "2027-01-01T12:00:00Z",
    })
  );
  rejects(() => normalizeStructuredTask([]));
});
Deno.test("auth validates token with Supabase rather than trusting arbitrary Bearer", async () => {
  Deno.env.set("SUPABASE_URL", "https://example.test");
  Deno.env.set("SUPABASE_ANON_KEY", "test");
  assert(await authenticatedUser(new Request("https://test")) === null);
  let called = false;
  const stub = (async (_input: unknown, init?: RequestInit) => {
    called = true;
    assert(
      new Headers(init?.headers).get("authorization") === "Bearer invalid",
    );
    assert(init?.signal);
    return new Response("{}", { status: 401 });
  }) as typeof fetch;
  assert(
    await authenticatedUser(
          new Request("https://test", {
            headers: { Authorization: "Bearer invalid" },
          }),
          stub,
        ) === null && called,
  );
});
let sequence = 0;
function request(body: unknown) {
  return new Request("https://test", {
    method: "POST",
    body: JSON.stringify(body),
  });
}
const auth = async () => `test-${sequence++}`;
Deno.test("handler returns 400 for bad input, 401 for missing JWT and controlled 502 on provider failure", async () => {
  const never = async () => {
    throw new Error("secret transcript");
  };
  assert(
    (await handleTextRequest(request({ text: "a" }), {
      authenticatedUser: async () => null,
      structureTask: never,
    })).status === 401,
  );
  for (const text of ["", "a".repeat(6001)]) {
    assert(
      (await handleTextRequest(request({ ...context, text }), {
        authenticatedUser: auth,
        structureTask: never,
      })).status === 400,
    );
  }
  const response = await handleTextRequest(
    request({ ...context, text: "Buy milk" }),
    { authenticatedUser: auth, structureTask: never },
  );
  assert(
    response.status === 502 && !(await response.text()).includes("secret"),
  );
});
Deno.test("DeepSeek stub uses bounded request/context and returns compatible task", async () => {
  Deno.env.set("DEEPSEEK_API_KEY", "test");
  const stub = (async (_url: unknown, init?: RequestInit) => {
    assert(init?.signal);
    const body = JSON.parse(String(init?.body));
    assert(body.messages[1].content.includes(context.reference_instant));
    return Response.json({
      choices: [{
        message: {
          content: JSON.stringify({ title: "Buy milk", due_date: null }),
        },
      }],
    });
  }) as typeof fetch;
  const task = await structureTask(
    "Buy milk",
    parsingContext(context, true),
    stub,
  );
  const result = await handleTextRequest(
    request({ ...context, text: "Buy milk" }),
    {
      authenticatedUser: auth,
      structureTask: async () => task,
    },
  );
  const payload = await result.json();
  assert(
    result.status === 200 && payload.success === true &&
      payload.task.title === "Buy milk" &&
      Array.isArray(payload.task.participant_hints),
  );
});

Deno.test("image URLs permit existing project storage buckets and reject SSRF targets", () => {
  const base = "https://project.supabase.co";
  for (
    const path of [
      "sign/create-task-from-images/user/photo.jpg?token=secret",
      "public/task-attachments/photo.jpg",
    ]
  ) {
    assert(
      validateImageURL(`${base}/storage/v1/object/${path}`, base).origin ===
        base,
    );
  }
  for (
    const value of [
      "http://169.254.169.254/latest/meta-data",
      "https://evil.test/storage/v1/object/sign/b/x",
      `${base}/auth/v1/admin`,
      "https://user:password@project.supabase.co/storage/v1/object/public/b/x",
    ]
  ) {
    rejects(() => validateImageURL(value, base));
  }
  assert(
    validateImageURL(
      "http://127.0.0.1:54321/storage/v1/object/sign/b/x",
      "http://127.0.0.1:54321",
    ).protocol === "http:",
  );
});
