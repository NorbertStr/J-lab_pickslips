// Service worker PWA: działa offline po pierwszym uruchomieniu.
// - nawigacja i pliki aplikacji: najpierw sieć, przy braku sieci – kopia z cache
// - przy każdej udanej odpowiedzi cache jest odświeżany
const CACHE = 'pick-slip-v1';
const CORE = ['./', 'index.html', 'manifest.json', 'flutter_bootstrap.js', 'favicon.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(CORE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Cache'ujemy własne pliki i CanvasKit/fonty z CDN Google (potrzebne offline).
  const cacheable = url.origin === self.location.origin ||
    url.hostname.endsWith('gstatic.com') || url.hostname.endsWith('googleapis.com');
  if (!cacheable) return;

  event.respondWith(
    fetch(req)
      .then((res) => {
        if (res && (res.ok || res.type === 'opaque')) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() =>
        caches.match(req).then((hit) => hit ||
          (req.mode === 'navigate' ? caches.match('index.html') : Response.error()))
      )
  );
});
