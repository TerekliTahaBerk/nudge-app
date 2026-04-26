// Just Gentle Reminders — Service Worker
// Handles: offline caching, background notification scheduling, notification clicks.

const CACHE = 'jgr-v1';
const PRECACHE = ['/', '/index.html', '/manifest.json', '/icon.svg'];

// ---------- Lifecycle ----------

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(PRECACHE).catch(() => {}))
  );
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => clients.claim())
  );
});

self.addEventListener('fetch', e => {
  // Cache-first for same-origin GET requests only
  if (e.request.method !== 'GET' || !e.request.url.startsWith(self.location.origin)) return;
  e.respondWith(
    caches.match(e.request).then(cached => cached || fetch(e.request).then(res => {
      if (res.ok) {
        const clone = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, clone));
      }
      return res;
    }))
  );
});

// ---------- Scheduled notifications ----------
// The app posts SCHEDULE messages with { id, title, body, delay }.
// We store them and fire via setTimeout (best-effort — SW may be killed).
// The app also re-schedules on each open so missed nudges are recovered.

const pending = new Map(); // id → timeoutId

self.addEventListener('message', e => {
  const msg = e.data;
  if (!msg) return;

  if (msg.type === 'SCHEDULE') {
    const { id, title, body, delay } = msg;
    // Clear any existing timer for this id
    if (pending.has(id)) { clearTimeout(pending.get(id)); pending.delete(id); }
    const t = setTimeout(() => {
      pending.delete(id);
      self.registration.showNotification(title, {
        body,
        icon: '/icon.svg',
        tag: `jgr-${id}`,
        requireInteraction: false,
        silent: false,
        data: { id },
      });
    }, Math.max(0, delay));
    pending.set(id, t);
  }

  if (msg.type === 'CANCEL') {
    if (pending.has(msg.id)) { clearTimeout(pending.get(msg.id)); pending.delete(msg.id); }
  }
});

// ---------- Notification interaction ----------

self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cs => {
      if (cs.length > 0) return cs[0].focus();
      return clients.openWindow('/');
    })
  );
});
