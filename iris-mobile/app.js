import { createCatalogClient, createDevicePreferenceStore, createStorageCache, DEVICES, routeActionLabel } from "./manifest.js";

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
const devicePreference = typeof localStorage === "undefined" ? undefined : createDevicePreferenceStore(localStorage);
const client = createCatalogClient({ cache });
const savedDevice = devicePreference?.read();
if (savedDevice) state.device = savedDevice;

function setStatus(message) { status.textContent = message; }

function showCatalogStatus() {
  if (!state.result) return;
  const freshness = state.result.stale || state.result.offline ? "Offline or refresh failed. Showing the last saved catalog" : "Catalog ready";
  setStatus(`${freshness}. Showing ${deviceLabels[state.device]}.`);
}

function textElement(tag, text, className) {
  const element = document.createElement(tag);
  element.textContent = text;
  if (className) element.className = className;
  return element;
}

function syncDeviceButtons() {
  for (const candidate of document.querySelectorAll("[data-device]")) {
    candidate.setAttribute("aria-pressed", String(candidate.dataset.device === state.device));
  }
}

function renderRoute(app) {
  const route = app.routes[state.device];
  const routeBox = document.createElement("div");
  routeBox.className = "route-box";
  const isAvailable = route.status === "verified" && route.destination;
  const unavailableCopy = {
    iphone: "No iPhone download is listed here.",
    android: "No Android download is listed here.",
    computer: "No computer download is listed here.",
  };
  routeBox.append(textElement("p", isAvailable ? "Ready to continue" : unavailableCopy[state.device], "route-state"));
  if (isAvailable) {
    const link = document.createElement("a");
    link.className = "route-link";
    link.href = route.destination;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.textContent = routeActionLabel(route.kind);
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
      const sourceParts = [];
      if (app.source.guideSlug) sourceParts.push(`guide ${app.source.guideSlug}`);
      sourceParts.push(app.source.revision ? `commit ${app.source.revision.slice(0, 12)}` : "commit pin unknown");
      if (app.source.releaseTag) sourceParts.push(`release ${app.source.releaseTag}`);
      details.append(textElement("p", `Observed source: ${sourceParts.join(" · ")}`, "source-label"));
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
  const fallbackIcon = textElement("span", app.icon.kind === "fallback" ? app.icon.label : app.title[0]?.toUpperCase() || "?", "app-icon");
  fallbackIcon.setAttribute("aria-hidden", "true");
  if (app.icon.kind === "url") {
    const image = document.createElement("img");
    image.src = app.icon.url;
    image.alt = "";
    image.width = 48;
    image.height = 48;
    image.loading = "lazy";
    image.decoding = "async";
    image.referrerPolicy = "no-referrer";
    image.className = "app-icon";
    image.addEventListener("error", () => image.replaceWith(fallbackIcon));
    head.append(image);
  } else {
    head.append(fallbackIcon);
  }
  const title = document.createElement("div");
  title.className = "app-title";
  title.append(textElement("h2", app.title));
  head.append(title);
  card.append(head);
  const support = app.os.length === 0 ? "unknown" : app.os.includes(state.device) ? "compatible" : "unavailable";
  const compatibilityCopy = {
    compatible: `${deviceLabels[state.device]} support observed`,
    unavailable: `${deviceLabels[state.device]} support unavailable`,
    unknown: `${deviceLabels[state.device]} support unknown`,
  };
  card.append(textElement("p", compatibilityCopy[support], `compatibility ${support}`));
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
  const shown = `${manifest.apps.length} app${manifest.apps.length === 1 ? "" : "s"}`;
  manifestNote.textContent = manifest.truncated ? `${manifest.label} · Showing first ${shown} of ${manifest.totalApps}` : `${manifest.label} · ${shown}`;
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
    errorCopy.textContent = loadError.code === "offline-no-cache" ? "You are offline and no verified catalog is cached yet." : "The live catalog could not be verified. Try again when the server is available.";
    setStatus("Catalog unavailable.");
  }
}

for (const button of document.querySelectorAll("[data-device]")) {
  button.addEventListener("click", () => {
    state.device = button.dataset.device;
    devicePreference?.write(state.device);
    syncDeviceButtons();
    if (state.result) render();
    showCatalogStatus();
  });
}

syncDeviceButtons();
$("refresh").addEventListener("click", () => loadCatalog({ force: true }));
$("retry").addEventListener("click", () => loadCatalog({ force: true }));
window.addEventListener("online", () => { setStatus("Connection restored. Refresh to verify the catalog."); });
window.addEventListener("offline", () => { setStatus("Offline. Showing verified metadata if it is cached."); loadCatalog(); });

loadCatalog();

export { renderCard, loadCatalog, client, state };
