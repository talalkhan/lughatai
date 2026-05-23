// LughatAI — Push notification handler
// This file is merged into the Workbox SW by next-pwa's custom worker option.
// Handles: push events (WoTD notification), notificationclick, notificationclose.

self.addEventListener("push", (event) => {
  if (!event.data) return;

  let payload;
  try {
    payload = event.data.json();
  } catch {
    payload = { title: "LughatAI", body: event.data.text() };
  }

  const { title = "LughatAI", body = "Word of the Day is ready!", word, url } = payload;

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: "/icons/icon-192.png",
      badge: "/icons/icon-192.png",
      tag: "wotd",          // replaces any existing WoTD notification
      renotify: true,
      data: { url: url ?? (word ? `/word/${word}` : "/") },
      actions: [
        { action: "open", title: "See word" },
        { action: "dismiss", title: "Dismiss" },
      ],
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  if (event.action === "dismiss") return;

  const targetUrl = event.notification.data?.url ?? "/";

  event.waitUntil(
    clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((windowClients) => {
        // Focus an existing window if one is already open
        for (const client of windowClients) {
          if (client.url.includes(self.location.origin) && "focus" in client) {
            client.navigate(targetUrl);
            return client.focus();
          }
        }
        // Otherwise open a new window
        if (clients.openWindow) return clients.openWindow(targetUrl);
      })
  );
});
