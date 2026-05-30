const JSON_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store'
};

export function acceptedResponse(): Response {
  return new Response(JSON.stringify({ ok: true }), {
    status: 202,
    headers: JSON_HEADERS
  });
}

export function failureResponse(status: number): Response {
  return new Response(JSON.stringify({ ok: false, error: 'Request could not be accepted.' }), {
    status,
    headers: JSON_HEADERS
  });
}

