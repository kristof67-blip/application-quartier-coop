// Service worker minimal : permet l'installation sur l'écran d'accueil.
// Il ne met RIEN en cache : le site est toujours lu depuis le réseau, donc jamais d'ancienne version.
self.addEventListener("install", function () { self.skipWaiting(); });
self.addEventListener("activate", function (e) { e.waitUntil(self.clients.claim()); });
self.addEventListener("fetch", function () {});
