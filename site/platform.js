// Platform switcher: shows the screens and text for the Mac or Android TV.
// No storage: the choice lives in the address (#mac, #android-tv) and nowhere else.
// Without JavaScript the page shows the Mac, and the switcher stays hidden.
(() => {
  const root = document.documentElement;
  const switcher = document.querySelector(".platforms");
  if (!switcher) return;
  const keys = [...switcher.querySelectorAll("button[data-platform]")];
  const known = keys.map((k) => k.dataset.platform);
  const hashes = { mac: "#mac", tv: "#android-tv" };

  const set = (platform, remember) => {
    if (!known.includes(platform)) platform = "mac";
    root.dataset.platform = platform;
    for (const key of keys) key.setAttribute("aria-pressed", String(key.dataset.platform === platform));
    if (remember) history.replaceState(null, "", hashes[platform] || location.pathname);
  };

  const fromAddress = () => {
    const hash = location.hash.toLowerCase();
    if (hash === "#android-tv" || hash === "#tv") return "tv";
    if (hash === "#mac") return "mac";
    return null;
  };
  const fromDevice = () => /Android/i.test(navigator.userAgent) && /\bTV\b|AFT|BRAVIA|SHIELD|Chromecast/i.test(navigator.userAgent) ? "tv" : null;

  set(fromAddress() || fromDevice() || "mac", false);
  switcher.hidden = false;
  for (const key of keys) key.addEventListener("click", () => set(key.dataset.platform, true));
  for (const link of document.querySelectorAll("a[data-switch]")) {
    link.addEventListener("click", (event) => {
      event.preventDefault();
      set(link.dataset.switch, true);
      document.getElementById("main").scrollIntoView({ behavior: "smooth" });
    });
  }
  addEventListener("hashchange", () => { const p = fromAddress(); if (p) set(p, false); });
})();
