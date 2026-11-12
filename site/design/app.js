/* Note Bubble — landing page behaviour.
   A small re-implementation of the app's own rules: GridLayout (masonry),
   AgingPalette (hue 0.33 → 0), Motion (springs and delays), PopBurst, PopSounds. */
(() => {
"use strict";

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch {} },
};

/* ================= Motion: real springs, as SwiftUI defines them ================= */
const linearOK = window.CSS && CSS.supports("transition-timing-function", "linear(0, 1)");
function spring(response, damping) {
  if (reduceMotion) return { duration: 180, easing: "ease-in-out" };
  const k = (2 * Math.PI / response) ** 2, c = 4 * Math.PI * damping / response;
  let x = 0, v = 0, t = 0; const dt = 1 / 1000, xs = [];
  while (t < 2.5) {
    v += (k * (1 - x) - c * v) * dt; x += v * dt; t += dt; xs.push(x);
    if (t > 0.05 && Math.abs(1 - x) < 0.001 && Math.abs(v) < 0.02) break;
  }
  if (!linearOK) return { duration: response * 1400, easing: "cubic-bezier(.34,1.4,.64,1)" };
  const n = 48, pts = ["0"];
  for (let i = 1; i < n; i++) pts.push(xs[Math.floor(i / n * (xs.length - 1))].toFixed(4));
  pts.push("1");
  return { duration: t * 1000, easing: `linear(${pts.join(",")})` };
}
const Motion = {
  reflow: spring(0.34, 0.74),
  resize: spring(0.30, 0.78),
  lift: spring(0.30, 0.70),
  toast: spring(0.32, 0.80),
  popHold: 550, burst: 420, burstLifetime: 500, toastLifetime: 4000,
  workspacePreview: 260, expandDelay: 180, collapseDelay: 450,
};

/* Animate a property from wherever it is now, so interrupted motion retargets smoothly. */
function animateTo(el, props, spec) {
  const cs = getComputedStyle(el);
  const from = {};
  for (const p in props) from[p] = cs[p];
  el._anims?.forEach(a => a.cancel());
  Object.assign(el.style, props);
  const a = el.animate([from, props], { duration: spec.duration, easing: spec.easing });
  el._anims = [a];
  return a;
}

/* ================= Ageing ================= */
const AGING_AFTER = 3, RED_AFTER = 7;
const agingAfter = w => w * AGING_AFTER / RED_AFTER;
const progress = (days, w) => Math.pow(clamp(days / w, 0, 1), 0.85);
const stageOf = (days, w) => days < agingAfter(w) ? 0 : days < w ? 1 : 2; // fresh, ageing, overdue
function hsb(h, s, b) {
  const f = n => { const k = (n + h * 6) % 6; return b - b * s * Math.max(0, Math.min(k, 4 - k, 1)); };
  return `rgb(${Math.round(f(5) * 255)},${Math.round(f(3) * 255)},${Math.round(f(1) * 255)})`;
}
const hue = (d, w) => 0.33 * (1 - progress(d, w));
const tint = (d, w = 7) => hsb(hue(d, w), 0.72, 0.92);
const shade = (d, w = 7) => hsb(hue(d, w), 0.88, 0.66);
const stageDays = [0, (AGING_AFTER + RED_AFTER) / 2, RED_AFTER];
const stageTint = s => tint(stageDays[s]), stageShade = s => shade(stageDays[s]);
const stageNames = ["fresh", "ageing", "overdue"];
function relAge(days) {
  const d = Math.floor(days);
  if (d < 1) return "today"; if (d === 1) return "yesterday"; if (d < 7) return d + "d";
  if (d < 30) return Math.floor(d / 7) + "w"; if (d < 365) return Math.floor(d / 30) + "mo";
  return Math.floor(d / 365) + "y";
}

/* ================= Sound: five pops, never the same twice running ================= */
const Sound = {
  ctx: null, buffers: [], analyser: null, last: -1, fallback: [],
  muted: store.get("nb-muted") === "1",
  names: [1, 2, 3, 4, 5].map(i => `assets/sounds/pop-${i}.mp3`),
  init() {
    if (this.ctx) { this.ctx.state === "suspended" && this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    this.ctx = new AC();
    this.analyser = this.ctx.createAnalyser(); this.analyser.fftSize = 64;
    this.analyser.connect(this.ctx.destination);
    this.names.forEach((u, i) => fetch(u).then(r => r.arrayBuffer()).then(b => this.ctx.decodeAudioData(b))
      .then(buf => { this.buffers[i] = buf; }).catch(() => {}));
  },
  pick() {
    let i = Math.floor(Math.random() * 5);
    if (i === this.last) i = (i + 1 + Math.floor(Math.random() * 4)) % 5;
    return i;
  },
  play(i = this.pick(), force = false) {
    this.last = i;
    if (this.muted && !force) return i;
    this.init();
    const buf = this.buffers[i];
    if (this.ctx && buf) {
      const src = this.ctx.createBufferSource(); src.buffer = buf;
      src.playbackRate.value = 0.94 + Math.random() * 0.12;
      src.connect(this.analyser); src.start();
    } else {
      const a = new Audio(this.names[i]); a.play().catch(() => {});
    }
    Wave.kick();
    return i;
  },
  setMuted(m) { this.muted = m; store.set("nb-muted", m ? "1" : "0"); syncMute(); },
};
addEventListener("pointerdown", () => Sound.init(), { once: true, capture: true });

/* ================= PopBurst: ring + ten shards ================= */
function burst(parent, cx, cy, w, h, radius, color) {
  const box = document.createElement("div");
  box.className = "burst"; box.style.left = cx + "px"; box.style.top = cy + "px";
  const ring = document.createElement("div");
  ring.className = "ring";
  Object.assign(ring.style, { width: w + "px", height: h + "px", left: -w / 2 + "px", top: -h / 2 + "px", borderRadius: radius + "px", borderColor: color, borderWidth: "3px" });
  box.appendChild(ring);
  const ease = "cubic-bezier(.2,.7,.3,1)";
  ring.animate([{ transform: "scale(1)", opacity: .9, borderWidth: "3px" }, { transform: `scale(${reduceMotion ? 1 : 1.6})`, opacity: 0, borderWidth: ".5px" }], { duration: Motion.burst, easing: ease, fill: "forwards" });
  if (!reduceMotion) {
    const m = Math.max(w, h);
    for (let i = 0; i < 10; i++) {
      const a = i / 10 * Math.PI * 2, s = document.createElement("div");
      s.className = "shard"; s.style.background = color; s.style.left = s.style.top = "-4px";
      box.appendChild(s);
      const at = (p) => `translate(${Math.cos(a) * m * (0.4 + p * 0.6)}px, ${Math.sin(a) * m * (0.4 + p * 0.6)}px) rotate(${a + p * 1.2}rad) scale(${1 - p * 0.6})`;
      s.animate([{ transform: at(0), opacity: .95 }, { transform: at(1), opacity: 0 }], { duration: Motion.burst, easing: ease, fill: "forwards" });
    }
  }
  parent.appendChild(box);
  setTimeout(() => box.remove(), Motion.burstLifetime + 40);
}

/* ================= Tiles: TileFace ================= */
const S = 1.3; // demo scale over the app's points
const G = { col: 94, minH: 64, maxH: 216, wide: 148, step: 8, inset: 9, chrome: 34, font: 11 };
const corner = (w, h, s) => Math.min(Math.min(w, h) * 0.26, 26 * s);

const measurer = document.createElement("div");
Object.assign(measurer.style, { position: "absolute", left: "-9999px", top: "0", visibility: "hidden", whiteSpace: "pre-wrap", overflowWrap: "anywhere", fontWeight: "600", lineHeight: "1.3", fontFamily: getComputedStyle(document.documentElement).getPropertyValue("--ui") });
document.body.appendChild(measurer);
const measureCache = new Map();
function textHeight(text, width, s) {
  const key = text + "|" + width.toFixed(1) + "|" + s;
  if (measureCache.has(key)) return measureCache.get(key);
  measurer.style.fontSize = G.font * s + "px"; measurer.style.width = width + "px";
  measurer.textContent = text || "New bubble";
  const h = measurer.getBoundingClientRect().height;
  measureCache.set(key, h);
  return h;
}

/* GridLayout: whole-column widths, measured heights, shortest-column masonry. */
function layout(nodes, width, s = S) {
  const spacing = 10 * s, pref = G.col * s;
  const cols = Math.max(1, Math.floor((width + spacing) / (pref + spacing)));
  const colW = (width - spacing * (cols - 1)) / cols;
  const spanW = n => colW * n + spacing * (n - 1);
  const heightFor = (text, w) => {
    const need = textHeight(text, w - G.inset * s * 2, s) + G.chrome * s;
    const step = G.step * s;
    return clamp(Math.ceil(need / step) * step, G.minH * s, G.maxH * s);
  };
  const bottoms = Array(cols).fill(0);
  const frames = nodes.map(n => {
    let span = 1, w = spanW(1), h = heightFor(n.text, w);
    if (h > G.wide * s && cols >= 2) { span = 2; w = spanW(2); h = heightFor(n.text, w); }
    let best = 0, bestTop = Infinity;
    for (let c = 0; c + span <= cols; c++) {
      const top = Math.max(...bottoms.slice(c, c + span));
      if (top < bestTop - 0.5) { bestTop = top; best = c; }
    }
    for (let c = best; c < best + span; c++) bottoms[c] = bestTop + h + spacing;
    return { x: best * (colW + spacing), y: bestTop, w, h };
  });
  return { frames, height: Math.max(0, ...bottoms) - spacing };
}

function tileHTML() {
  return `<div class="body"><div class="face"><span class="streak"></span></div><div class="label"><div class="text"></div><div class="foot"></div></div></div>`;
}
function paint(el, node, win = 7, s = S) {
  el.style.setProperty("--tint", tint(node.days, win));
  el.style.setProperty("--shade", shade(node.days, win));
  const t = el.querySelector(".text");
  if (t.contentEditable !== "true") t.textContent = node.text || "New bubble";
  const overdue = stageOf(node.days, win) === 2;
  el.querySelector(".foot").innerHTML =
    (overdue ? `<span class="bang">!</span>` : "") + `<span>${relAge(node.days)}</span>` +
    (node.children?.length ? `<span class="count">${node.children.length}</span>` : "");
  el.setAttribute("aria-label", `${node.text}, ${relAge(node.days)}${node.children?.length ? `, ${node.children.length} inside` : ""}`);
}
function staticGrid(container, nodes, win, s) {
  container.innerHTML = "";
  const w = container.clientWidth;
  if (!w) return;
  const { frames, height } = layout(nodes, w, s);
  nodes.forEach((n, i) => {
    const f = frames[i], el = document.createElement("div");
    el.className = "tile"; el.innerHTML = tileHTML();
    Object.assign(el.style, { width: f.w + "px", height: f.h + "px", transform: `translate(${f.x}px,${f.y}px)`, borderRadius: corner(f.w, f.h, s) + "px" });
    el.querySelector(".text").style.fontSize = G.font * s + "px";
    paint(el, n, win, s);
    container.appendChild(el);
  });
  return height;
}

/* ================= Data: three boards, like Scripts/demo-data.py ================= */
let uid = 0;
const N = (text, days, children = []) => ({ id: "n" + (++uid), text, days, children });
function seed() {
  return [
    { name: "Work", win: 7, nodes: [
      N("Hold me to pop ✦", 0.3),
      N("Q3 roadmap", 4.2, [N("Draft milestones", 1), N("Ask design for mocks", 5.1), N("Pricing page copy", 8.5, [N("Headline", 2), N("FAQ", 9)]), N("Review with Priya", 0.5)]),
      N("Book the dentist", 9.4),
      N("Fix the flaky login test before Friday's release", 2.1),
      N("Drag me around — then shake me", 7.6),
      N("Reply to Sam", 0),
      N("Read that long article about masonry layouts and why rows leave a gap under every short tile — it has been open in a tab for ages", 5.6),
      N("Pay invoice #2041", 11),
      N("Water the plants", 3.4),
    ]},
    { name: "Home", win: 7, nodes: [
      N("Groceries", 1, [N("Oat milk", 1), N("Lemons", 1), N("Bread", 0)]),
      N("Fix the bike's back brake", 9),
      N("Plan the weekend trip", 2.5),
      N("Return parcel", 4.5),
      N("Call Mum", 0.2),
    ]},
    { name: "Someday", win: 90, nodes: [
      N("Learn the cello", 40),
      N("Write a short novel", 95),
      N("Visit Lisbon", 12),
    ]},
  ];
}

/* ================= The panel ================= */
const panel = $("#panel"), grid = $("#grid"), viewport = $("#viewport");
const flight = document.createElement("div");
Object.assign(flight.style, { position: "absolute", inset: "0", pointerEvents: "none", zIndex: 50 });
panel.appendChild(flight);

const P = {
  boards: seed(), bi: 0, path: [], els: new Map(), undo: null, editing: null,
  drag: null, press: null, preview: null, active: false,
};
const board = () => P.boards[P.bi];
function listAt(b, path) {
  let list = b.nodes;
  for (const id of path) list = list.find(n => n.id === id)?.children ?? list;
  return list;
}
const cur = () => listAt(board(), P.path);
function walk(nodes, fn) { nodes.forEach(n => { fn(n); walk(n.children, fn); }); }
function worst(b) { let w = -1; walk(b.nodes, n => { w = Math.max(w, stageOf(n.days, b.win)); }); return w; }

function makeTile(node) {
  const el = document.createElement("div");
  el.className = "tile"; el.innerHTML = tileHTML() + `<button class="edit" title="Rename" aria-label="Rename">✎</button>`;
  el.dataset.id = node.id; el.tabIndex = 0; el.setAttribute("role", "button");
  el.addEventListener("pointerdown", e => onTileDown(e, node, el));
  el.querySelector(".edit").addEventListener("pointerdown", e => { e.stopPropagation(); e.preventDefault(); startEdit(node, el); });
  el.addEventListener("keydown", e => { if (e.key === "Enter" && !P.editing) { e.preventDefault(); open(node); } });
  return el;
}

/* Lay the current level out and move every tile to its slot on a spring. */
function render({ enter = false, instant = false } = {}) {
  const list = cur(), w = viewport.clientWidth;
  const { frames, height } = layout(list, w);
  const seen = new Set();
  list.forEach((node, i) => {
    seen.add(node.id);
    let el = P.els.get(node.id), fresh = false;
    if (!el) { el = makeTile(node); P.els.set(node.id, el); grid.appendChild(el); fresh = true; }
    paint(el, node, board().win);
    const f = frames[i]; el._frame = f;
    if (el.parentNode === flight) return; // the tile in the hand follows the pointer, not the grid
    const props = { transform: `translate(${f.x}px,${f.y}px)`, width: f.w + "px", height: f.h + "px", borderRadius: corner(f.w, f.h, S) + "px" };
    if (fresh || instant) {
      Object.assign(el.style, props); el._target = JSON.stringify(props);
      if (fresh && (enter || node._new)) {
        el.querySelector(".body").animate([{ transform: "scale(.4)", opacity: 0 }, { transform: "scale(1)", opacity: 1 }],
          { ...Motion.lift, delay: enter ? i * 28 : 0, fill: "backwards" });
        delete node._new;
      }
    } else {
      const key = JSON.stringify(props);
      if (el._target !== key) animateTo(el, props, P.editing === node ? Motion.resize : Motion.reflow);
      el._target = key;
    }
  });
  for (const [id, el] of P.els) if (!seen.has(id) && el.parentNode !== flight) { el.remove(); P.els.delete(id); }
  grid.style.height = height + "px";
  viewport.style.height = Math.max(height, 150) + "px";
  let empty = $(".empty-state", viewport);
  if (!list.length) {
    if (!empty) { empty = document.createElement("div"); empty.className = "empty-state"; viewport.appendChild(empty); }
    empty.innerHTML = P.path.length ? "<div><b>Nothing inside yet</b>Double-click to add a sub-bubble</div>" : "<div><b>All clear ✦</b>Double-click, or press +, for a new bubble</div>";
  } else empty?.remove();
  renderBar();
}

function renderBar() {
  const b = board(), counts = [0, 0, 0];
  walk(b.nodes, n => counts[stageOf(n.days, b.win)]++);
  $("#badges").innerHTML = counts.map((c, s) => c ? `<span class="badge${s === 2 ? " pulse" : ""}" title="${c} ${stageNames[s]}" style="background:linear-gradient(135deg,${stageTint(s)},${stageShade(s)})">${c}</span>` : "").join("");
  const crumbs = [b.name]; let list = b.nodes;
  for (const id of P.path) { const n = list.find(x => x.id === id); if (!n) break; crumbs.push(n.text); list = n.children; }
  $("#crumbs").innerHTML = crumbs.length > 1 ? crumbs.map((c, i) => i === crumbs.length - 1 ? `<span class="here">${esc(c)}</span>` : `<button data-depth="${i}">${esc(c)}</button> ›`).join(" ") : "";
  $("#backBtn").hidden = !P.path.length;
  $("#wsChip").innerHTML = `${esc(b.name)} <small>▾</small>`;
  $("#undoBtn").hidden = !P.undo;
  $("#dots").innerHTML = P.boards.map((x, i) => {
    const w = worst(x);
    return `<button class="dot${i === P.bi ? " current" : ""}" data-i="${i}" title="${esc(x.name)}" style="background:${w < 0 ? "rgba(255,255,255,.35)" : `linear-gradient(135deg,${stageTint(w)},${stageShade(w)})`}"></button>`;
  }).join("");
  syncCounts();
}
const esc = s => s.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

/* ---------- Navigation: in and out of bubbles, across boards ---------- */
function transition(dir, change) {
  // dir: "in" | "out" | "left" | "right"
  const out = { in: "scale(.92)", out: "scale(1.06)", left: "translateX(-28%)", right: "translateX(28%)" }[dir];
  const inFrom = { in: "scale(1.06)", out: "scale(.92)", left: "translateX(28%)", right: "translateX(-28%)" }[dir];
  grid.animate([{ transform: "none", opacity: 1 }, { transform: reduceMotion ? "none" : out, opacity: 0 }], { duration: 150, easing: "ease-in" }).onfinish = () => {
    P.els.forEach(el => el.remove()); P.els.clear();
    change(); render({ instant: true });
    grid.animate([{ transform: reduceMotion ? "none" : inFrom, opacity: 0 }, { transform: "none", opacity: 1 }], Motion.reflow);
  };
}
function open(node) { transition("in", () => P.path.push(node.id)); }
function up(toDepth = P.path.length - 1) { if (P.path.length) transition("out", () => { P.path = P.path.slice(0, Math.max(0, toDepth)); }); }
function goBoard(i) {
  i = clamp(i, 0, P.boards.length - 1);
  if (i === P.bi || P.drag) return; // nothing changes the board on screen mid-drag
  const dir = i > P.bi ? "left" : "right";
  transition(dir, () => { P.bi = i; P.path = []; });
}

/* ---------- One gesture: tap, hold and drag ---------- */
function onTileDown(e, node, el) {
  if (e.button !== 0 || P.editing === node || P.drag) return;
  if (P.editing) finishEdit();
  e.preventDefault();
  P.active = true;
  const body = el.querySelector(".body");
  const start = { x: e.clientX, y: e.clientY, t: performance.now() };
  const press = P.press = { node, el, body, start, p: 0, done: false, raf: 0 };
  const tick = () => {
    if (P.press !== press) return;
    press.p = clamp((performance.now() - start.t) / Motion.popHold, 0, 1);
    const p = press.p * press.p; // swell slowly, then commit
    body.style.transform = `scale(${1 + p * 0.22}) rotate(${p * 1.5}deg)`;
    if (press.p >= 1) { press.done = true; endPress(false); requestPop(node, el); return; }
    press.raf = requestAnimationFrame(tick);
  };
  press.raf = requestAnimationFrame(tick);

  const move = ev => {
    if (press.done) return;
    const dx = ev.clientX - start.x, dy = ev.clientY - start.y;
    if (!P.drag && Math.hypot(dx, dy) > 5) { endPress(true); beginDrag(node, el, ev); }
    if (P.drag) dragMove(ev);
  };
  const upH = ev => {
    removeEventListener("pointermove", move); removeEventListener("pointerup", upH); removeEventListener("pointercancel", upH);
    if (P.drag) return endDrag(ev);
    if (press.done) return; // a hold consumes its release
    endPress(true);
    if (ev.type === "pointerup") open(node);
  };
  addEventListener("pointermove", move); addEventListener("pointerup", upH); addEventListener("pointercancel", upH);
}
function endPress(springBack) {
  const pr = P.press; if (!pr) return;
  cancelAnimationFrame(pr.raf); P.press = null;
  if (springBack && pr.p > 0.02) { const t = pr.body.style.transform; pr.body.style.transform = ""; pr.body.animate([{ transform: t }, { transform: "none" }], Motion.lift); }
  else pr.body.style.transform = "";
}

/* ---------- Popping ---------- */
function requestPop(node, el) {
  const unpopped = []; walk(node.children, n => unpopped.push(n));
  if (unpopped.length) confirmPop(node, unpopped.length, () => pop(node, el), () => { el.querySelector(".body").animate([{ transform: "scale(1.22) rotate(1.5deg)" }, { transform: "none" }], Motion.lift); });
  else pop(node, el);
}
function pop(node, el) {
  const list = cur(), idx = list.indexOf(node);
  if (idx < 0) return;
  const pr = panel.getBoundingClientRect(), r = el.getBoundingClientRect(), f = el._frame;
  burst(panel, r.left - pr.left + r.width / 2, r.top - pr.top + r.height / 2, f.w * 1.22, f.h * 1.22, corner(f.w, f.h, S), tint(node.days, board().win));
  Sound.play();
  list.splice(idx, 1);
  el.remove(); P.els.delete(node.id);
  setUndo(`Popped “${trunc(node.text)}”`, () => { list.splice(idx, 0, node); node._new = true; });
  render();
}
const trunc = (t, n = 22) => t.length > n ? t.slice(0, n - 1) + "…" : t;
function confirmPop(node, count, yes, no) {
  const c = $("#confirm");
  $("#confirmText").textContent = `“${trunc(node.text, 30)}” still has ${count} bubble${count === 1 ? "" : "s"} inside. They'll go with it.`;
  c.classList.add("show");
  const done = ok => { c.classList.remove("show"); $("#confirmYes").onclick = $("#confirmNo").onclick = null; ok ? yes() : no(); };
  $("#confirmYes").onclick = () => done(true);
  $("#confirmNo").onclick = () => done(false);
}

/* ---------- Undo: one action, with a toast ---------- */
let toastTimer;
function setUndo(text, restore, toast = true) {
  P.undo = { restore, text };
  if (toast) {
    $("#toastText").textContent = text;
    $("#toast").classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => $("#toast").classList.remove("show"), Motion.toastLifetime);
  }
  renderBar();
}
function undo() {
  if (!P.undo) return;
  const u = P.undo; P.undo = null; u.restore();
  $("#toast").classList.remove("show");
  render();
}

/* ---------- Drag: rearrange, shake, file onto another board ---------- */
function panelPoint(ev) { const r = panel.getBoundingClientRect(); return { x: ev.clientX - r.left, y: ev.clientY - r.top }; }
function beginDrag(node, el, ev) {
  const pr = panel.getBoundingClientRect(), r = el.getBoundingClientRect(), f = el._frame;
  const p = panelPoint(ev);
  const origin = { x: r.left - pr.left + (r.width - f.w) / 2, y: r.top - pr.top + (r.height - f.h) / 2 };
  el._anims?.forEach(a => a.cancel());
  flight.appendChild(el);
  el.style.transform = `translate(${origin.x}px,${origin.y}px)`;
  el.classList.add("lifted");
  el.querySelector(".body").animate([{ transform: "scale(1)" }, { transform: "scale(1.08)" }], { ...Motion.lift, fill: "forwards" });
  P.drag = { node, el, grab: { x: p.x - origin.x, y: p.y - origin.y }, home: P.bi, hist: [], dot: null, dotTimer: 0 };
}
function dragMove(ev) {
  const d = P.drag, p = panelPoint(ev);
  const x = p.x - d.grab.x, y = p.y - d.grab.y;
  d.el.style.transform = `translate(${x}px,${y}px)`;
  shake(d, ev.clientX, performance.now());

  // Over a workspace dot? Rest there and that board slides in behind the tile.
  const hit = document.elementFromPoint(ev.clientX, ev.clientY);
  const dot = hit?.closest?.(".dot");
  const di = dot ? +dot.dataset.i : null;
  $$(".dot", $("#dots")).forEach(x => x.classList.toggle("target", x === dot));
  if (di !== d.dot) {
    d.dot = di; clearTimeout(d.dotTimer);
    if (di !== null) d.dotTimer = setTimeout(() => showPreview(di === d.home ? null : di), Motion.workspacePreview);
  }
  if (P.preview !== null) return;

  // Rearrange: the slot under the pointer is where this tile goes.
  const vr = viewport.getBoundingClientRect(), gx = ev.clientX - vr.left, gy = ev.clientY - vr.top;
  const list = cur(), from = list.indexOf(d.node);
  for (const [id, el] of P.els) {
    if (id === d.node.id) continue;
    const f = el._frame; if (!f) continue;
    if (gx >= f.x && gx <= f.x + f.w && gy >= f.y && gy <= f.y + f.h) {
      const to = list.findIndex(n => n.id === id);
      if (to !== from && to >= 0 && !d.cool) {
        list.splice(from, 1); list.splice(to, 0, d.node); render();
        d.cool = true; setTimeout(() => { d.cool = false; }, 120);
      }
      break;
    }
  }
}
function shake(d, x, t) {
  d.hist.push({ x, t }); d.hist = d.hist.filter(h => t - h.t < 700);
  let rev = 0, dir = 0, anchor = d.hist[0].x;
  for (const h of d.hist) { const dx = h.x - anchor; if (Math.abs(dx) > 14) { const s = Math.sign(dx); if (dir && s !== dir) rev++; dir = s; anchor = h.x; } }
  if (rev >= 3 && d.node.days > 0.05) {
    d.hist = []; d.node.days = 0; paint(d.el, d.node, board().win);
    d.el.classList.remove("flash"); void d.el.offsetWidth; d.el.classList.add("flash");
    renderBar();
  }
}
function showPreview(i) {
  if (P.preview === i) return;
  P.preview = i;
  let pv = $(".grid.preview", viewport);
  if (i === null) {
    if (pv) pv.animate([{ transform: "none", opacity: 1 }, { transform: "translateX(30%)", opacity: 0 }], { duration: 160 }).onfinish = () => pv.remove();
    grid.animate([{ transform: "translateX(-30%)", opacity: 0 }, { transform: "none", opacity: 1 }], Motion.reflow);
    grid.style.opacity = 1;
    return;
  }
  if (!pv) { pv = document.createElement("div"); pv.className = "grid preview"; viewport.appendChild(pv); }
  grid.animate([{ opacity: getComputedStyle(grid).opacity }, { opacity: 0, transform: "translateX(-30%)" }], { duration: 160, fill: "forwards" });
  grid.style.opacity = 0;
  const b = P.boards[i];
  staticGrid(pv, b.nodes, b.win, S);
  if (!b.nodes.length) pv.innerHTML = `<div class="empty-state"><div><b>${esc(b.name)}</b>Let go to file it here</div></div>`;
  pv.animate([{ transform: "translateX(30%)", opacity: 0 }, { transform: "none", opacity: 1 }], Motion.reflow);
}
function endDrag(ev) {
  const d = P.drag; clearTimeout(d.dotTimer);
  $$(".dot", $("#dots")).forEach(x => x.classList.remove("target"));
  const target = P.preview;
  const body = d.el.querySelector(".body");
  if (target !== null && target !== undefined) {
    // File it on the other board: it shrinks into that board's dot.
    const list = cur(), idx = list.indexOf(d.node);
    list.splice(idx, 1); P.boards[target].nodes.unshift(d.node);
    const dot = $(`.dot[data-i="${target}"]`), pr = panel.getBoundingClientRect(), dr = dot.getBoundingClientRect();
    const tx = dr.left - pr.left + dr.width / 2 - d.el._frame.w / 2, ty = dr.top - pr.top + dr.height / 2 - d.el._frame.h / 2;
    const el = d.el, node = d.node, from = P.boards[target];
    P.drag = null;
    animateTo(el, { transform: `translate(${tx}px,${ty}px)` }, Motion.lift);
    body.animate([{ transform: "scale(1.08)", opacity: 1 }, { transform: "scale(.05)", opacity: 0 }], { duration: 300, easing: "ease-in", fill: "forwards" }).onfinish = () => { el.remove(); P.els.delete(node.id); };
    showPreview(null);
    setUndo(`Moved to ${from.name}`, () => { from.nodes.splice(from.nodes.indexOf(node), 1); list.splice(idx, 0, node); node._new = true; });
    render();
    return;
  }
  // Put it down in its slot.
  const el = d.el, vr = viewport.getBoundingClientRect(), pr = panel.getBoundingClientRect();
  P.drag = null;
  render();
  const f = el._frame;
  const dest = `translate(${vr.left - pr.left + f.x}px,${vr.top - pr.top + f.y}px)`;
  body.getAnimations().forEach(a => a.cancel());
  body.animate([{ transform: "scale(1.08)" }, { transform: "none" }], Motion.lift);
  animateTo(el, { transform: dest }, Motion.lift).onfinish = () => {
    if (!el.isConnected || P.drag?.el === el) return;
    el.classList.remove("lifted"); el._target = null;
    el.style.transform = `translate(${f.x}px,${f.y}px)`;
    if (P.els.get(d.node.id) === el) grid.appendChild(el); else el.remove();
  };
}

/* ---------- Writing: saved on every keystroke; ⏎ finishes, Esc reverts ---------- */
function addBubble() {
  if (P.editing) finishEdit();
  const n = N("", 0); n._new = true;
  cur().unshift(n); render();
  startEdit(n, P.els.get(n.id));
}
function startEdit(node, el) {
  if (P.editing && P.editing !== node) finishEdit();
  P.editing = node; P.active = true;
  const t = el.querySelector(".text");
  node._before = node.text;
  t.contentEditable = "true"; t.textContent = node.text;
  const hint = document.createElement("span"); hint.className = "done-hint"; hint.textContent = "⏎ done"; el.querySelector(".body").appendChild(hint);
  t.focus();
  const r = document.createRange(); r.selectNodeContents(t); r.collapse(false);
  const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r);
  t.oninput = () => { node.text = t.innerText.replace(/\n$/, ""); render(); };
  t.onkeydown = e => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); finishEdit(); }
    else if (e.key === "Escape") { e.preventDefault(); node.text = node._before; finishEdit(); }
    e.stopPropagation();
  };
  t.onblur = () => setTimeout(() => P.editing === node && finishEdit(), 0);
}
function finishEdit() {
  const node = P.editing; if (!node) return;
  P.editing = null;
  const el = P.els.get(node.id);
  if (el) {
    const t = el.querySelector(".text"); t.contentEditable = "false"; t.oninput = t.onkeydown = t.onblur = null;
    el.querySelector(".done-hint")?.remove();
  }
  if (!node.text.trim()) { // an empty bubble quietly goes away
    const list = cur(), i = list.indexOf(node);
    if (i >= 0) list.splice(i, 1);
    if (el) el.querySelector(".body").animate([{ transform: "scale(1)", opacity: 1 }, { transform: "scale(.4)", opacity: 0 }], { duration: 160, fill: "forwards" }).onfinish = () => render();
    else render();
    return;
  }
  render();
}

/* ---------- Bar controls ---------- */
$("#addBtn").onclick = addBubble;
$("#backBtn").onclick = () => up();
$("#undoBtn").onclick = undo;
$("#toastUndo").onclick = undo;
$("#crumbs").onclick = e => { const b = e.target.closest("button"); if (b) up(+b.dataset.depth); };
$("#wsChip").onclick = () => goBoard((P.bi + 1) % P.boards.length);
$("#dots").onclick = e => { const d = e.target.closest(".dot"); if (d) goBoard(+d.dataset.i); };
$("#shuffleBtn").onclick = () => {
  const list = cur(), before = list.slice();
  for (let i = list.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [list[i], list[j]] = [list[j], list[i]]; }
  setUndo("Shuffled", () => { list.splice(0, list.length, ...before); }, false);
  render();
};
$("#muteBtn").onclick = () => Sound.setMuted(!Sound.muted);
function syncMute() {
  $(".wv", $("#muteBtn")).style.display = Sound.muted ? "none" : "";
  $(".x", $("#muteBtn")).style.display = Sound.muted ? "" : "none";
  $("#muteBtn").title = Sound.muted ? "Unmute pop sounds" : "Mute pop sounds";
  $("#mbMute small").textContent = Sound.muted ? "✓" : "";
}
viewport.addEventListener("dblclick", e => { if (!e.target.closest(".tile")) addBubble(); });

/* Two-finger swipe: horizontal scroll, intercepted before anything else sees it. */
let wheelAcc = 0, wheelLock = false, wheelQuiet;
panel.addEventListener("wheel", e => {
  if (Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return;
  e.preventDefault();
  clearTimeout(wheelQuiet); wheelQuiet = setTimeout(() => { wheelAcc = 0; wheelLock = false; }, 220);
  if (wheelLock) return;
  wheelAcc += e.deltaX;
  if (Math.abs(wheelAcc) > 40) { wheelLock = true; goBoard(P.bi + Math.sign(wheelAcc)); wheelAcc = 0; }
}, { passive: false });
/* …and with a mouse or finger, a horizontal drag across empty space. */
viewport.addEventListener("pointerdown", e => {
  if (e.target.closest(".tile")) return;
  const x0 = e.clientX;
  const mv = ev => { if (Math.abs(ev.clientX - x0) > 60) { goBoard(P.bi + (ev.clientX < x0 ? 1 : -1)); off(); } };
  const off = () => { removeEventListener("pointermove", mv); removeEventListener("pointerup", off); };
  addEventListener("pointermove", mv); addEventListener("pointerup", off);
});
panel.addEventListener("pointerenter", () => { P.active = true; });
document.addEventListener("pointerdown", e => { if (!panel.contains(e.target)) P.active = false; });

addEventListener("keydown", e => {
  if (!P.active || P.editing) return;
  const cmd = e.metaKey || e.ctrlKey;
  if (cmd && e.key.toLowerCase() === "z") { e.preventDefault(); undo(); }
  else if (cmd && e.key === "ArrowLeft") { e.preventDefault(); goBoard(P.bi - 1); }
  else if (cmd && e.key === "ArrowRight") { e.preventDefault(); goBoard(P.bi + 1); }
  else if ((cmd && e.key.toLowerCase() === "n") || (!cmd && e.key.toLowerCase() === "n" && e.target === document.body)) { e.preventDefault(); addBubble(); }
  else if (e.key === "Escape") up();
});

/* ================= Hero flourishes ================= */
(function heroWords() {
  const w = $("#ageWord");
  let t = 0;
  setInterval(() => { t = (t + 1) % 8; w.style.color = tint(t, 7); }, 900);
  w.style.color = tint(0, 7);
  const pw = $("#popWord");
  pw.style.cursor = "pointer"; pw.title = "Pop it";
  pw.addEventListener("click", () => {
    const r = pw.getBoundingClientRect();
    burst(document.body, r.left + r.width / 2 + scrollX, r.top + r.height / 2 + scrollY, r.width, r.height * .8, 24, "#ff4d8d");
    Sound.play();
    pw.animate([{ transform: "scale(1.25) rotate(2deg)" }, { transform: "scale(0)", opacity: 0, offset: .25 }, { transform: "scale(0)", opacity: 0, offset: .6 }, { transform: "none", opacity: 1 }], { duration: 1100, easing: "cubic-bezier(.34,1.4,.64,1)" });
  });
  document.body.style.position = "relative";
})();

/* Ambient soap bubbles: drift up, pop on click. */
(function floaters() {
  const host = $("#floaters"), list = [];
  const count = innerWidth < 700 ? 7 : 13;
  const spawn = (b, initial) => {
    b.r = 14 + Math.random() * 46;
    b.x = Math.random() * innerWidth; b.y = initial ? Math.random() * innerHeight : innerHeight + b.r * 2;
    b.v = 8 + Math.random() * 18; b.phase = Math.random() * 6.28; b.sway = 10 + Math.random() * 24;
    Object.assign(b.el.style, { width: b.r * 2 + "px", height: b.r * 2 + "px", opacity: 0.35 + Math.random() * 0.45 });
  };
  for (let i = 0; i < count; i++) {
    const el = document.createElement("div"); el.className = "floater"; host.appendChild(el);
    const b = { el }; spawn(b, true); list.push(b);
  }
  document.addEventListener("pointerdown", e => {
    if (e.target.closest("button,a,input,.tile,.panel,.glass,.desk,.sbubble,h1,h2,h3,p,li,kbd,code")) return;
    for (const b of list) {
      const cx = b.x + Math.sin(b.phase) * b.sway + b.r, cy = b.y + b.r;
      if (Math.hypot(e.clientX - cx, e.clientY - cy) < b.r) {
        burst(host, cx, cy, b.r * 2, b.r * 2, b.r, "rgba(192,140,255,.9)"); Sound.play(); spawn(b, false); break;
      }
    }
  });
  let last = performance.now();
  const step = now => {
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    for (const b of list) {
      if (!reduceMotion) { b.y -= b.v * dt; b.phase += dt * 0.6; }
      if (b.y < -b.r * 2 - 10) spawn(b, false);
      b.el.style.transform = `translate(${b.x + Math.sin(b.phase) * b.sway}px,${b.y}px)`;
    }
    requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
})();

/* ================= Ageing section ================= */
(function ageing() {
  const host = $("#ageTileHost");
  const node = { text: "Renew passport", days: 0, children: [] };
  host.innerHTML = `<div class="tile">${tileHTML()}</div>`;
  const el = host.firstElementChild, body = $(".body", el);
  const windows = [[3, "3 days"], [7, "1 week"], [14, "2 weeks"], [30, "1 month"], [90, "3 months"]];
  let win = 7;
  const slider = $("#ageSlider"), note = $("#shakeNote");
  const maxDays = () => win * 1.43;
  const update = () => {
    node.days = slider.value / 100 * maxDays();
    const s = stageOf(node.days, win);
    node.text = ["Renew passport", "Renew passport (soon…)", "Renew passport!!"][s];
    paint(el, node, win, 1.55);
    $("#legend").innerHTML = stageNames.map((n, i) => `<span style="opacity:${i === s ? 1 : .45}"><i style="background:${stageTint(i)}"></i>${n[0].toUpperCase() + n.slice(1)}</span>`).join("");
  };
  const fmt = d => d < 1 ? "today" : d >= 30 ? Math.round(d / 30) + "mo" : d >= 14 ? Math.round(d / 7) + "w" : Math.round(d) + "d";
  const scale = () => { $("#ageScale").innerHTML = [0, agingAfter(win), win, maxDays()].map(fmt).map((t, i) => `<span>${i === 2 ? "overdue · " + t : i === 1 ? "ageing · " + t : t}</span>`).join(""); };
  $("#windowSeg").innerHTML = windows.map(([d, l]) => `<button data-d="${d}" class="${d === 7 ? "on" : ""}">${l}</button>`).join("");
  $("#windowSeg").onclick = e => {
    const b = e.target.closest("button"); if (!b) return;
    const keep = node.days; win = +b.dataset.d;
    $$("button", $("#windowSeg")).forEach(x => x.classList.toggle("on", x === b));
    slider.value = clamp(keep / maxDays() * 100, 0, 100); scale(); update();
  };
  slider.oninput = update;
  scale(); update();

  // Shake to reset.
  let drag = null;
  el.addEventListener("pointerdown", e => {
    e.preventDefault(); el.setPointerCapture(e.pointerId);
    drag = { x0: e.clientX, y0: e.clientY, hist: [], node };
    body.animate([{ transform: "scale(1)" }, { transform: "scale(1.08)" }], { ...Motion.lift, fill: "forwards" });
    el.style.cursor = "grabbing";
  });
  el.addEventListener("pointermove", e => {
    if (!drag) return;
    el.style.transform = `translate(${e.clientX - drag.x0}px,${(e.clientY - drag.y0) * .4}px)`;
    const t = performance.now();
    drag.hist.push({ x: e.clientX, t }); drag.hist = drag.hist.filter(h => t - h.t < 700);
    let rev = 0, dir = 0, a = drag.hist[0].x;
    for (const h of drag.hist) { const dx = h.x - a; if (Math.abs(dx) > 14) { const s = Math.sign(dx); if (dir && s !== dir) rev++; dir = s; a = h.x; } }
    if (rev >= 3 && node.days > 0) {
      drag.hist = [];
      slider.value = 0; update();
      el.classList.remove("flash"); void el.offsetWidth; el.classList.add("flash");
      note.textContent = "✓ Fresh again — reset to today";
    }
  });
  const release = () => {
    if (!drag) return; drag = null; el.style.cursor = "";
    body.getAnimations().forEach(a => a.cancel());
    body.animate([{ transform: "scale(1.08)" }, { transform: "none" }], Motion.lift);
    animateTo(el, { transform: "translate(0px,0px)" }, Motion.lift);
  };
  el.addEventListener("pointerup", release); el.addEventListener("pointercancel", release);

  // The first time it scrolls into view, age it through a whole window.
  let played = false;
  new IntersectionObserver(([en]) => {
    if (!en.isIntersecting || played) return; played = true;
    const t0 = performance.now(), dur = 2600;
    const run = now => {
      const p = clamp((now - t0) / dur, 0, 1);
      slider.value = (p < .5 ? 2 * p * p : 1 - (-2 * p + 2) ** 2 / 2) * 86; update();
      if (p < 1) requestAnimationFrame(run); else note.textContent = "Grab the bubble and shake it ↔";
    };
    requestAnimationFrame(run);
  }, { threshold: .5 }).observe(host);
})();

/* ================= Workspaces section ================= */
(function workspaces() {
  const boards = seed(), track = $("#wsTrack"), dots = $("#wsDots"), wrap = $("#wsWrap");
  let i = 0, auto = true;
  track.innerHTML = boards.map(b => `<div class="ws-page"><h4>${b.name}<small>overdue after ${b.win === 90 ? "3 months" : "1 week"}</small></h4><div class="ws-mini"></div></div>`).join("");
  const draw = () => $$(".ws-mini", track).forEach((m, k) => { const h = staticGrid(m, boards[k].nodes.slice(0, 7), boards[k].win, 1); m.style.height = Math.min(h ?? 0, 230) + "px"; m.style.overflow = "hidden"; });
  const go = (n, user = true) => {
    if (user) auto = false;
    i = (n + boards.length) % boards.length;
    track.style.transform = `translateX(${-i * 100}%)`;
    dots.innerHTML = boards.map((b, k) => { const w = worst(b); return `<button class="dot${k === i ? " current" : ""}" data-k="${k}" title="${b.name}" style="background:linear-gradient(135deg,${stageTint(w)},${stageShade(w)})"></button>`; }).join("");
  };
  dots.onclick = e => { const d = e.target.closest(".dot"); if (d) go(+d.dataset.k); };
  let acc = 0, lock = false, q;
  wrap.addEventListener("wheel", e => {
    if (Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return;
    e.preventDefault(); clearTimeout(q); q = setTimeout(() => { acc = 0; lock = false; }, 220);
    if (lock) return; acc += e.deltaX;
    if (Math.abs(acc) > 40) { lock = true; go(i + Math.sign(acc)); acc = 0; }
  }, { passive: false });
  wrap.addEventListener("pointerdown", e => {
    const x0 = e.clientX, w = wrap.clientWidth; wrap.setPointerCapture(e.pointerId);
    track.style.transition = "none";
    const mv = ev => { const dx = ev.clientX - x0; track.style.transform = `translateX(calc(${-i * 100}% + ${dx * ((i === 0 && dx > 0) || (i === boards.length - 1 && dx < 0) ? .3 : 1)}px))`; };
    const up = ev => {
      wrap.removeEventListener("pointermove", mv); wrap.removeEventListener("pointerup", up);
      track.style.transition = ""; const dx = ev.clientX - x0;
      go(Math.abs(dx) > w * .18 ? clamp(i + (dx < 0 ? 1 : -1), 0, boards.length - 1) : i, Math.abs(dx) > 4);
    };
    wrap.addEventListener("pointermove", mv); wrap.addEventListener("pointerup", up);
  });
  let inView = false;
  new IntersectionObserver(([en]) => { inView = en.isIntersecting; }, { threshold: .4 }).observe(wrap);
  addEventListener("keydown", e => { if (inView && !P.active && !e.metaKey && (e.key === "ArrowLeft" || e.key === "ArrowRight")) go(i + (e.key === "ArrowRight" ? 1 : -1)); });
  setInterval(() => { if (auto && inView && !reduceMotion) go(i + 1, false); }, 3200);
  draw(); go(0, false);
  addEventListener("resize", debounce(draw, 150));
})();

/* ================= Pill + menu bar ================= */
(function pill() {
  const host = $("#pillHost"), pillEl = $("#pill"), meter = $("#intentMeter"), label = $("#intentLabel"), desk = $("#desk");
  const mini = [ N("Book the dentist", 9.4), N("Reply to Sam", 0), N("Q3 roadmap", 4.2, [N("a", 1), N("b", 1)]), N("Pay invoice #2041", 11), N("Water the plants", 3.4), N("Fix flaky test", 2) ];
  let openTimer, closeTimer, isOpen = false, pinned = false;
  const counts = [0, 0, 0]; mini.forEach(n => counts[stageOf(n.days, 7)]++);
  $("#miniBadges").innerHTML = counts.map((c, s) => c ? `<span class="badge${s === 2 ? " pulse" : ""}" style="background:linear-gradient(135deg,${stageTint(s)},${stageShade(s)});height:16px;min-width:18px;font-size:9.5px">${c}</span>` : "").join("");
  const fill = (to, ms) => { meter.animate([{ width: getComputedStyle(meter).width }, { width: to }], { duration: ms, fill: "forwards", easing: "linear" }); };
  const doOpen = () => {
    isOpen = true; host.classList.remove("closing"); host.classList.add("open");
    label.textContent = "open — move away to fold";
    requestAnimationFrame(() => staticGrid($("#miniGrid"), mini, 7, 0.82));
  };
  const doClose = () => { isOpen = false; host.classList.add("closing"); host.classList.remove("open", "tip"); label.textContent = "hover the pill"; fill("0%", 120); };
  pillEl.addEventListener("pointerenter", () => {
    clearTimeout(closeTimer); if (isOpen) return;
    host.classList.add("tip"); label.textContent = "dwelling… 180 ms"; fill("100%", Motion.expandDelay);
    openTimer = setTimeout(doOpen, Motion.expandDelay);
  });
  pillEl.addEventListener("pointerleave", () => { if (!isOpen) { clearTimeout(openTimer); host.classList.remove("tip"); label.textContent = "hover the pill"; fill("0%", 120); } });
  host.addEventListener("pointerenter", () => { clearTimeout(closeTimer); if (isOpen) { label.textContent = "open — move away to fold"; fill("100%", 100); } });
  host.addEventListener("pointerleave", () => {
    if (!isOpen || pinned) return;
    label.textContent = "folding in 450 ms…"; fill("0%", Motion.collapseDelay);
    closeTimer = setTimeout(doClose, Motion.collapseDelay);
  });
  // Brightens as the pointer approaches.
  desk.addEventListener("pointermove", e => {
    const r = pillEl.getBoundingClientRect();
    const d = Math.hypot(e.clientX - (r.left + r.width / 2), e.clientY - (r.top + r.height / 2));
    pillEl.classList.toggle("near", d < 130);
  });
  desk.addEventListener("pointerleave", () => pillEl.classList.remove("near"));

  // Menu bar icon: click opens the grid, right-click for the menu.
  const svg = $("#mbSvg");
  svg.innerHTML = menuBarIcon();
  const icon = $("#mbIcon"), menu = $("#mbMenu");
  icon.addEventListener("click", e => {
    e.stopPropagation(); menu.classList.remove("show");
    if (isOpen) { pinned = false; doClose(); } else { pinned = true; doOpen(); label.textContent = "opened from the menu bar"; fill("100%", 100); }
  });
  icon.addEventListener("contextmenu", e => { e.preventDefault(); e.stopPropagation(); menu.classList.toggle("show"); icon.classList.toggle("open", menu.classList.contains("show")); });
  $("#mbMute").addEventListener("click", () => Sound.setMuted(!Sound.muted));
  document.addEventListener("click", e => { if (!menu.contains(e.target)) { menu.classList.remove("show"); icon.classList.remove("open"); } if (pinned && !host.contains(e.target) && e.target !== icon) { pinned = false; doClose(); } });
  const tick = () => { const d = new Date(); $("#clock").textContent = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }); };
  tick(); setInterval(tick, 30000);
})();

/* The menu bar icon: three bubbles with reflections cut out (MenuBarIcon.swift), y flipped. */
function menuBarIcon() {
  const bubbles = [[13.6, 12.6, 3.6], [14.0, 4.4, 2.4], [7.0, 7.2, 5.6]];
  let mask = `<rect width="18" height="18" fill="black"/>`;
  for (const [x, yy, r] of bubbles) {
    const y = 18 - yy;
    mask += `<circle cx="${x}" cy="${y}" r="${r + 0.9}" fill="black"/><circle cx="${x}" cy="${y}" r="${r}" fill="white"/>`;
    const pt = (deg, rr) => [x + Math.cos(deg * Math.PI / 180) * rr, y - Math.sin(deg * Math.PI / 180) * rr];
    const [ax, ay] = pt(110, r * .62), [bx, by] = pt(168, r * .62), [gx, gy] = pt(92, r * .62);
    mask += `<path d="M${ax} ${ay} A${r * .62} ${r * .62} 0 0 0 ${bx} ${by}" stroke="black" stroke-width="${Math.max(r * .2, .75)}" stroke-linecap="round" fill="none"/><circle cx="${gx}" cy="${gy}" r="${Math.max(r * .12, .45)}" fill="black"/>`;
  }
  return `<defs><mask id="mbm">${mask}</mask></defs><rect width="18" height="18" fill="currentColor" mask="url(#mbm)"/>`;
}
function syncCounts() {
  let overdue = 0, boards = 0;
  P.boards.forEach(b => { let o = 0; walk(b.nodes, n => { if (stageOf(n.days, b.win) === 2) o++; }); overdue += o; if (o) boards++; });
  $("#mbCount") && ($("#mbCount").textContent = overdue || "");
  $("#pillNum") && ($("#pillNum").textContent = overdue);
  const tip = $(".pill-tip"); if (tip) tip.textContent = `${overdue} overdue across ${P.boards.length} boards · opens on ${board().name}`;
}

/* ================= Sounds section ================= */
const Wave = {
  bars: [], raf: 0,
  init() { const w = $("#wave"); w.innerHTML = "<i></i>".repeat(14); this.bars = $$("i", w); },
  kick() {
    if (this.raf || !this.bars.length) return;
    const data = new Uint8Array(32); let quiet = 0;
    const step = () => {
      if (Sound.analyser) Sound.analyser.getByteFrequencyData(data);
      let sum = 0;
      this.bars.forEach((b, i) => { const v = data[i + 1] || 0; sum += v; b.style.height = 4 + v / 255 * 14 + "px"; });
      quiet = sum < 10 ? quiet + 1 : 0;
      this.raf = quiet > 30 ? 0 : requestAnimationFrame(step);
    };
    this.raf = requestAnimationFrame(step);
  },
};
(function sounds() {
  Wave.init();
  const g = $("#soundGrid");
  const looks = [[0, 118], [2.6, 96], [4.6, 132], [6.2, 104], [9, 122]];
  g.innerHTML = looks.map(([d, size], i) => `<button class="sbubble reveal" data-i="${i}" style="--size:${size}px;--c1:${tint(d)};--c2:${shade(d)};--d:${-i * .9}s;transition-delay:${i * 70}ms">pop-${i + 1}<small>${["soft", "bright", "deep", "quick", "wet"][i]}</small></button>`).join("");
  const popBtn = b => {
    const i = +b.dataset.i;
    if (b.classList.contains("popping") || b.classList.contains("gone")) return;
    b.classList.add("popping");
    setTimeout(() => {
      const r = b.getBoundingClientRect();
      burst(document.body, r.left + r.width / 2 + scrollX, r.top + r.height / 2 + scrollY, r.width * 1.1, r.height * 1.1, r.width / 2, getComputedStyle(b).getPropertyValue("--c1"));
      Sound.play(i, true);
      $("#nowPlaying").textContent = `pop-${i + 1}.mp3`;
      b.classList.remove("popping"); b.classList.add("gone");
      setTimeout(() => { b.classList.remove("gone"); b.classList.add("regrow"); b.style.transform = "scale(0)"; requestAnimationFrame(() => { b.style.transform = ""; }); setTimeout(() => b.classList.remove("regrow"), 600); }, 900);
    }, reduceMotion ? 0 : 200);
  };
  g.addEventListener("click", e => { const b = e.target.closest(".sbubble"); if (b) popBtn(b); });
  $("#randomPop").onclick = () => popBtn($(`.sbubble[data-i="${Sound.pick()}"]`, g));
  $("#popRain").onclick = () => $$(".sbubble", g).forEach((b, k) => setTimeout(() => popBtn(b), k * 110));
})();

/* ================= Shortcuts ================= */
$("#keyGrid").innerHTML = [
  ["Open a bubble", ["Click"]], ["Pop a bubble", ["Hold"]], ["Undo", ["⌘", "Z"]],
  ["New bubble", ["⌘", "N"]], ["New workspace", ["⌘", "⇧", "N"]], ["Switch board", ["⌘", "←", "→"]],
  ["Finish writing", ["⏎"]], ["Second line", ["⇧", "⏎"]], ["Discard an edit / go up", ["Esc"]],
  ["Show / hide anywhere", ["⌥", "Space"]], ["Minimise", ["⌘", "M"]], ["Reset a bubble's age", ["Shake"]],
].map(([t, k]) => `<div class="key-card glass reveal"><span>${t}</span><span class="k">${k.map(x => `<kbd>${x}</kbd>`).join("")}</span></div>`).join("");

/* ================= Install ================= */
$("#copyBtn").onclick = async () => {
  try { await navigator.clipboard.writeText($("#brewCmd").textContent); $("#copyBtn").textContent = "Copied ✓"; Sound.play(); }
  catch { $("#copyBtn").textContent = "Select & copy"; }
  setTimeout(() => { $("#copyBtn").textContent = "Copy"; }, 1800);
};

/* ================= Scroll reveal ================= */
const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } }), { threshold: .12 });
$$(".reveal").forEach((el, i) => io.observe(el));

function debounce(f, ms) { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => f(...a), ms); }; }
addEventListener("resize", debounce(() => { measureCache.clear(); render({ instant: true }); }, 120));

syncMute();
document.fonts?.ready.then(() => { measureCache.clear(); render({ instant: true }); });
render({ enter: true });
})();
