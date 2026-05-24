const MAX_TEXT_LENGTH = 900;

export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: {
      Allow: "POST, OPTIONS",
    },
  });
}

export async function onRequestGet() {
  return json({ ok: false, error: "Send a POST request with an email address." }, 405, {
    Allow: "POST, OPTIONS",
  });
}

export async function onRequestPost(context) {
  const { request, env } = context;
  const payload = await readPayload(request);

  if (clean(payload.website)) {
    return json({ ok: true }, 202);
  }

  const email = clean(payload.email).toLowerCase();
  if (!isEmail(email)) {
    return json({ ok: false, error: "Enter a valid email address." }, 400);
  }

  const contactEmail = clean(env.CONTACT_EMAIL) || "hello@anysee.bar";
  const waitlist = env.ANYSEE_WAITLIST;
  if (!waitlist || typeof waitlist.put !== "function") {
    return json({
      ok: false,
      error: "The waitlist storage binding is not configured yet.",
      contactEmail,
    }, 501);
  }

  const now = new Date().toISOString();
  const key = `lead:${await digest(email)}`;
  const existing = await waitlist.get(key, "json").catch(() => null);
  const record = {
    email,
    name: clean(payload.name),
    note: clean(payload.note),
    source: "anysee.bar",
    createdAt: existing && existing.createdAt ? existing.createdAt : now,
    updatedAt: now,
    userAgent: clean(request.headers.get("user-agent")),
    referrer: clean(request.headers.get("referer")),
  };

  await waitlist.put(key, JSON.stringify(record), {
    metadata: {
      updatedAt: now,
      source: "anysee.bar",
    },
  });

  return json({ ok: true });
}

async function readPayload(request) {
  const contentType = request.headers.get("content-type") || "";

  if (contentType.includes("application/json")) {
    try {
      return await request.json();
    } catch {
      return {};
    }
  }

  const formData = await request.formData();
  return Object.fromEntries(formData.entries());
}

function clean(value) {
  if (typeof value !== "string") return "";
  return value.trim().replace(/\s+/g, " ").slice(0, MAX_TEXT_LENGTH);
}

function isEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

async function digest(value) {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 32);
}

function json(body, status = 200, extraHeaders = {}) {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}
