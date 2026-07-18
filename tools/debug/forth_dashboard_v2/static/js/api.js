// Thin same-origin REST client. Every call targets /api/* only.
// Throws ApiError on non-2xx so callers can surface a message without crashing.

export class ApiError extends Error {
  constructor(message, status, body) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.body = body;
  }
}

async function request(method, path, body) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  let resp;
  try {
    resp = await fetch(path, opts);
  } catch (e) {
    // Network/backend-down: normalize to an ApiError with status 0.
    throw new ApiError('backend unreachable', 0, null);
  }
  const text = await resp.text();
  let data = null;
  if (text) {
    try { data = JSON.parse(text); } catch (_) { data = text; }
  }
  if (!resp.ok) {
    const msg = (data && data.detail) || (data && data.error) || resp.statusText || 'request failed';
    throw new ApiError(msg, resp.status, data);
  }
  return data;
}

export const api = {
  get:  (p)    => request('GET', p),
  post: (p, b) => request('POST', p, b),
  del:  (p, b) => request('DELETE', p, b),
};
