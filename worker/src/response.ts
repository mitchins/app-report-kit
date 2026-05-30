const JSON_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store'
};

function buildHeaders(extraHeaders?: HeadersInit): Headers {
  const headers = new Headers(JSON_HEADERS);
  if (extraHeaders) {
    new Headers(extraHeaders).forEach((value, key) => headers.set(key, value));
  }
  return headers;
}

export function acceptedResponse(extraHeaders?: HeadersInit): Response {
  return new Response(JSON.stringify({ ok: true }), {
    status: 202,
    headers: buildHeaders(extraHeaders)
  });
}

export function failureResponse(status: number, extraHeaders?: HeadersInit): Response {
  return new Response(JSON.stringify({ ok: false, error: 'Request could not be accepted.' }), {
    status,
    headers: buildHeaders(extraHeaders)
  });
}
