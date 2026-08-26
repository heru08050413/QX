/**
 * Shadowrocket YouTube encrypted-initplayback fallback.
 *
 * Scope: requests whose URL already matched the configuration's
 * googlevideo.com/initplayback ... &ack request rule.
 *
 * YouTube can deliver an encrypted playback-control response through this
 * endpoint.  That response cannot be filtered by the existing protobuf
 * youtubei/v1/player response hook.  Returning an empty 200 makes the client
 * fall back to the normal player API, where the pinned response hook removes
 * ad placements and preserves PiP/background-play flags.
 *
 * This script is deliberately local-only: it does not redirect, proxy, log,
 * persist, or upload request data, and it never modifies media segments.
 */

(() => {
  const url = typeof $request !== "undefined" ? $request.url || "" : "";
  const encryptedInitPlayback =
    /^https:\/\/[\w-]+\.googlevideo\.com\/initplayback(?:\?[^#]*)?[?&]ack(?:[=&][^#]*)?(?:#.*)?$/i;

  if (!encryptedInitPlayback.test(url)) {
    $done({});
    return;
  }

  $done({
    response: {
      status: 200,
      headers: {
        "Content-Type": "application/octet-stream",
        "Cache-Control": "no-store",
      },
      body: "",
    },
  });
})();
