import { createCatalogClient, createStorageCache, DEVICES } from "./manifest.js";

const deviceLabels = { iphone: "iPhone", android: "Android", computer: "Computer" };
const state = { device: "iphone", result: null };
const $ = (id) => document.getElementById(id);
const status = $("status");
const catalog = $("catalog");
const empty = $("empty");
const error = $("error");
const errorCopy = $("error-copy");
const manifestNote = $("manifest-note");
const cache = typeof localStorage === "undefined" ? undefined : createStorageCache(localStorage);
const client = createCatalogClient({ cache });

function setStatus(message) { status.textContent = message; }

function showCatalogStatus() {
  if (!state.result) return;
  const freshness = state.result.stale ? "Could not refresh. Showing the last saved catalog" : "Catalog ready";
  setStatus(`${freshness}. Showing ${deviceLabels[state.device]}.`);
}

function textElement(tag, text, className) {
  const element = document.createElement(tag);
  element.textContent = text;
  if (className) element.className = className;
  return element;
}

function renderRoute(app) {
  const route = app.routes[state.device];
  const routeBox = document.createElement("div");
  routeBox.className = "route-box";
  const isAvailable = route.status === "verified" && route.destination;
  const unavailableCopy = {
    iphone: "The iPhone beta download is not available yet.",
    android: "The Android package is not available yet.",
    computer: "No verified computer route is available yet.",
  };
  routeBox.append(textElement("p", isAvailable ? "Ready to continue" : unavailableCopy[state.device], "route-state"));
  if (isAvailable) {
    const link = document.createElement("a");
    link.className = "route-link";
    link.href = route.destination;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.textContent = route.kind === "web" ? "Open" : "Install";
    routeBox.append(link);
  } else {
    if (app.setupGuide) {
      const link = document.createElement("a");
      link.className = "route-link";
      link.href = app.setupGuide.destination;
      link.textContent = app.setupGuide.label;
      routeBox.append(link);
    }
    const actions = [...(route.nextActions || []), ...(app.setup[state.device] || [])];
    if (actions.length) {
      const details = document.createElement("details");
      details.className = "setup-details";
      details.append(textElement("summary", "Publisher setup details"));
      const list = document.createElement("ol");
      list.className = "next-actions";
      for (const action of [...new Set(actions)]) list.append(textElement("li", action));
      if (route.evidence) details.append(textElement("p", route.evidence, "route-evidence"));
      details.append(textElement("p", `Source guide ${app.source.guideSlug} · ${app.source.revision.slice(0, 12)}`, "source-label"));
      details.append(textElement("p", `Publisher next steps for ${deviceLabels[state.device]}:`, "route-evidence"), list);
      routeBox.append(details);
    }
  }
  return routeBox;
}

function renderCard(app) {
  const card = document.createElement("article");
  card.className = "app-card";
  const head = document.createElement("div");
  head.className = "app-head";
  const icon = textElement("span", app.icon.kind === "fallback" ? app.icon.label : "", "app-icon");
  icon.setAttribute("aria-hidden", "true");
  if (app.icon.kind === "url") {
    const image = document.createElement("img");
    image.src = app.icon.url;
    image.alt = "";
    image.width = 48;
    image.height = 48;
    image.className = "app-icon";
    image.addEventListener("error", () => image.replaceWith(icon));
    head.append(image);
  } else {
    head.append(icon);
  }
  const title = document.createElement("div");
  title.className = "app-title";
  title.append(textElement("h2", app.title));
  head.append(title);
  card.append(head);
  const supported = app.os.includes(state.device);
  card.append(textElement("p", supported ? `${deviceLabels[state.device]} route` : `${deviceLabels[state.device]} support unavailable`, `compatibility ${supported ? "compatible" : "unknown"}`));
  card.append(renderRoute(app));
  return card;
}

function render() {
  catalog.replaceChildren();
  empty.hidden = true;
  error.hidden = true;
  const manifest = state.result?.manifest;
  if (!manifest || manifest.apps.length === 0) {
    empty.hidden = false;
    return;
  }
  for (const app of manifest.apps) catalog.append(renderCard(app));
  manifestNote.textContent = `${manifest.label} · ${manifest.apps.length} app${manifest.apps.length === 1 ? "" : "s"}`;
}

async function loadCatalog({ force = false } = {}) {
  setStatus(force ? "Refreshing catalog…" : "Loading catalog…");
  try {
    const result = await client.load({ force, offline: typeof navigator !== "undefined" && navigator.onLine === false });
    state.result = result;
    render();
    showCatalogStatus();
  } catch (loadError) {
    state.result = null;
    render();
    error.hidden = false;
    errorCopy.textContent = loadError.code === "offline-no-cache" ? "You are offline and no verified catalog is cached yet." : "The local catalog could not be verified. Try again when the server is available.";
    setStatus("Catalog unavailable.");
  }
}

for (const button of document.querySelectorAll("[data-device]")) {
  button.addEventListener("click", () => {
    state.device = button.dataset.device;
    for (const candidate of document.querySelectorAll("[data-device]")) candidate.setAttribute("aria-pressed", String(candidate === button));
    if (state.result) render();
    showCatalogStatus();
  });
}
$("refresh").addEventListener("click", () => loadCatalog({ force: true }));
$("retry").addEventListener("click", () => loadCatalog({ force: true }));
window.addEventListener("online", () => { setStatus("Connection restored. Refresh to verify the catalog."); });
window.addEventListener("offline", () => { setStatus("Offline. Showing verified metadata if it is cached."); loadCatalog(); });

loadCatalog();

export { renderCard, loadCatalog, client, state };
