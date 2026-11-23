// Service Worker: App-Hülle offline verfügbar halten, API immer live.
const CACHE = "echowp-trainer-v1";
const SHELL = ["/", "/static/app.css", "/static/app.js", "/static/icons/logo.svg",
  "/static/fonts/inter-latin-400-normal.woff2", "/static/fonts/inter-latin-700-normal.woff2",
  "/static/fonts/inter-latin-900-normal.woff2"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)));
  self.skipWaiting();
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))));
  self.clients.claim();
});
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.pathname.startsWith("/api/") || url.pathname.endsWith(".ics")) return;
  e.respondWith(
    fetch(e.request).then((res) => {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(e.request, copy));
      return res;
    }).catch(() => caches.match(e.request))
  );
});
