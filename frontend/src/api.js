const BASE_URL = "http://127.0.0.1:8000";

function authHeaders(token) {
  return { Authorization: `Bearer ${token}` };
}

async function parseOrThrow(res) {
  if (!res.ok) {
    let detail = res.statusText;
    try {
      const body = await res.json();
      if (typeof body.detail === "string") {
        detail = body.detail;
      } else if (Array.isArray(body.detail)) {
        // FastAPI/Pydantic validation errors: a list of {loc, msg, ...}.
        detail = body.detail
          .map((d) => (d.msg ? d.msg.replace(/^Value error, /, "") : JSON.stringify(d)))
          .join("; ");
      } else if (body.detail) {
        detail = JSON.stringify(body.detail);
      }
    } catch {
      // ignore - no JSON body
    }
    throw new Error(detail);
  }
  return res.json();
}

export async function login(username, password) {
  const form = new URLSearchParams();
  form.set("username", username);
  form.set("password", password);
  const res = await fetch(`${BASE_URL}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });
  return parseOrThrow(res);
}

export async function fetchProcedures(token) {
  const res = await fetch(`${BASE_URL}/procedures`, { headers: authHeaders(token) });
  return parseOrThrow(res);
}

export async function fetchOperations(token) {
  const res = await fetch(`${BASE_URL}/operations`, { headers: authHeaders(token) });
  return parseOrThrow(res);
}

export async function registerOperation(token, procedureId, scheduledStart) {
  const res = await fetch(`${BASE_URL}/operations`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders(token) },
    body: JSON.stringify({ procedure_id: procedureId, scheduled_start: scheduledStart }),
  });
  return parseOrThrow(res);
}

export async function fetchOperationDetail(token, operationId) {
  const res = await fetch(`${BASE_URL}/operations/${operationId}`, { headers: authHeaders(token) });
  return parseOrThrow(res);
}
