/* EchoWP Trainer – Web-App (ohne Build-Schritt, reines JavaScript) */
"use strict";

const $ = (sel, el = document) => el.querySelector(sel);
const view = $("#view");
const state = { day: isoToday(), weekStart: null };

const WEEKDAYS = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];
const KIND_LABEL = { kraft: "Functional/Kraft", cardio: "Ausdauer", intervall: "Intervalle", marsch: "Marsch", mobility: "Mobility",
  lauf: "Lauf", gehen: "Gehen/Marsch", sonstiges: "Sonstiges" };

/* ---------- Hilfen ---------- */
function isoToday() { return toIso(new Date()); }
function toIso(d) { const z = new Date(d.getTime() - d.getTimezoneOffset() * 60000); return z.toISOString().slice(0, 10); }
function addDays(iso, n) { const d = new Date(iso + "T12:00:00"); d.setDate(d.getDate() + n); return toIso(d); }
function mondayOf(iso) { const d = new Date(iso + "T12:00:00"); const wd = (d.getDay() + 6) % 7; return addDays(iso, -wd); }
function fmtDate(iso, opts = { weekday: "long", day: "numeric", month: "long" }) {
  return new Date(iso + "T12:00:00").toLocaleDateString("de-DE", opts);
}
function esc(s) { return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function dur(s) { if (!s) return ""; const m = Math.round(s / 60); return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min`; }
function km(m) { return m ? `${(m / 1000).toFixed(1).replace(".", ",")} km` : ""; }
function num(v, d = 0) { return v === null || v === undefined ? "–" : Number(v).toLocaleString("de-DE", { maximumFractionDigits: d }); }

function token() { try { return localStorage.getItem("trainerToken") || ""; } catch { return ""; } }
async function api(path, opts = {}) {
  const headers = Object.assign({}, opts.headers || {});
  if (token()) headers.Authorization = "Bearer " + token();
  if (opts.json !== undefined) { headers["Content-Type"] = "application/json"; opts.body = JSON.stringify(opts.json); }
  const res = await fetch(path, { ...opts, headers });
  if (res.status === 401) { askToken(); throw new Error("Nicht angemeldet"); }
  if (!res.ok) { let msg = res.statusText; try { msg = (await res.json()).detail || msg; } catch {} throw new Error(msg); }
  return res.json();
}
function askToken() {
  const t = prompt("Zugangscode für EchoWP Trainer (TRAINER_TOKEN):");
  if (t) { try { localStorage.setItem("trainerToken", t.trim()); } catch {} location.reload(); }
}
let toastTimer;
function toast(msg, err = false) {
  const t = $("#toast"); t.textContent = msg; t.className = "toast show" + (err ? " err" : "");
  clearTimeout(toastTimer); toastTimer = setTimeout(() => (t.className = "toast"), 3200);
}
function rpeBar(v) {
  if (!v) return "";
  let s = '<span class="rpe" aria-label="RPE ' + v + ' von 10">';
  for (let i = 1; i <= 10; i++) s += `<i class="${i <= v ? "on" : ""}"></i>`;
  return s + `</span> <span class="small muted">RPE ${v}</span>`;
}
function sessionCard(s, opts = {}) {
  const ex = (s.exercises || []).map((e) => `<tr><td>${esc(e.name)}</td><td>${esc(e.detail || "")}</td></tr>`).join("");
  return `<div class="session kind-${esc(s.kind)} ${s.status === "erledigt" ? "done" : ""}" data-id="${s.id}">
    <div class="spread"><h3>${esc(s.title)}</h3>${s.status && s.status !== "geplant" ? `<span class="chip">${esc(s.status)}</span>` : ""}</div>
    <div class="meta">${esc(s.start || "")}–${esc(s.end || "")} · ${esc(KIND_LABEL[s.kind] || s.kind)} ${s.rpe ? "· " + (opts.compact ? `RPE ${s.rpe}` : rpeBar(s.rpe)) : ""}</div>
    ${s.focus ? `<p class="small" style="margin:8px 0 0">${esc(s.focus)}</p>` : ""}
    ${ex && !opts.compact ? `<table class="ex">${ex}</table>` : ""}
    ${opts.actions ? `<div class="row" style="margin-top:10px">
      <button class="btn btn-small" data-status="erledigt">Erledigt</button>
      <button class="btn btn-ghost btn-small" data-status="ausgelassen">Ausgelassen</button></div>` : ""}
  </div>`;
}
function bindSessionActions(root, reload) {
  root.querySelectorAll("[data-status]").forEach((b) => b.addEventListener("click", async () => {
    const id = b.closest(".session").dataset.id;
    await api(`/api/sessions/${id}/status`, { method: "PUT", json: { status: b.dataset.status } });
    toast("Gespeichert"); reload();
  }));
}

/* ---------- Kopfleiste ---------- */
function setSync(last, source) {
  const el = $("#syncState");
  if (!last) { el.textContent = source ? "noch nicht synchronisiert" : "keine Garmin-Verbindung"; el.className = "sync-state"; return; }
  const t = new Date(last.ts).toLocaleString("de-DE", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  el.textContent = `${last.ok ? "Garmin" : "Fehler"} · ${t}`;
  el.title = last.message || "";
  el.className = "sync-state " + (last.ok ? "ok" : "err");
  $("#syncBtn").title = el.textContent;
}
$("#syncBtn").addEventListener("click", async () => {
  const b = $("#syncBtn"); b.disabled = true;
  try {
    const r = await api("/api/sync", { method: "POST" });
    toast(r.message, !r.ok);
    route();
  } catch (e) { toast(e.message, true); } finally { b.disabled = false; }
});

/* ---------- Heute ---------- */
function ring(score) {
  const r = 52, c = 2 * Math.PI * r, v = score ?? 0;
  return `<div class="ring"><svg viewBox="0 0 120 120" aria-hidden="true">
    <circle cx="60" cy="60" r="${r}" fill="none" stroke="#2A2A2A" stroke-width="11"/>
    <circle cx="60" cy="60" r="${r}" fill="none" stroke="#FFD400" stroke-width="11" stroke-linecap="round"
      stroke-dasharray="${(c * v) / 100} ${c}"/></svg>
    <div class="num"><div><b>${score ?? "–"}</b><span>von 100</span></div></div></div>`;
}
function spark(trend) {
  const pts = trend.filter((p) => p.score !== null);
  if (pts.length < 2) return '<p class="muted small">Noch zu wenig Daten für einen Verlauf.</p>';
  const W = 300, H = 80, n = trend.length;
  const x = (i) => 6 + (i * (W - 12)) / (n - 1), y = (v) => H - 6 - ((v - 0) * (H - 12)) / 100;
  let d = "", dots = "";
  trend.forEach((p, i) => { if (p.score === null) return; d += (d ? "L" : "M") + x(i).toFixed(1) + " " + y(p.score).toFixed(1); });
  const last = trend.map((p, i) => [p, i]).filter(([p]) => p.score !== null).pop();
  dots = `<circle class="dot" cx="${x(last[1])}" cy="${y(last[0].score)}" r="4"/>`;
  return `<svg class="spark" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="Bereitschaft der letzten 14 Tage">
    <line class="base" x1="0" x2="${W}" y1="${y(50)}" y2="${y(50)}"/><path class="line" d="${d}"/>${dots}</svg>
    <div class="spread small muted"><span>${fmtDate(trend[0].date, { day: "numeric", month: "short" })}</span><span>Linie = 50</span><span>heute</span></div>`;
}
async function renderHeute() {
  view.innerHTML = '<div class="loading">Lade Daten …</div>';
  const d = await api(`/api/dashboard?day=${state.day}`);
  setSync(d.last_sync, d.live_source);
  const r = d.readiness, comp = r.components || {};
  const compRows = [["sleep", "Schlaf"], ["hrv", "HRV"], ["rhr", "Ruhepuls"], ["body_battery", "Body Battery"], ["subjective", "Gefühl"]]
    .map(([k, l]) => `<div class="bar"><span>${l}</span><div class="track"><div class="fill" style="width:${comp[k] ?? 0}%"></div></div><b>${comp[k] ?? "–"}</b></div>`).join("");
  const m = d.metrics || {};
  const isToday = d.date === isoToday();
  const n = d.nutrition;
  const run = d.running || {};
  const marches = run.marches || {};

  view.innerHTML = `
  <div class="datebar">
    <button class="btn btn-ghost btn-small" id="prev" aria-label="Vortag">‹</button>
    <h1>${isToday ? "Heute" : esc(fmtDate(d.date))}</h1>
    <button class="btn btn-ghost btn-small" id="next" aria-label="Folgetag" ${isToday ? "disabled" : ""}>›</button>
  </div>
  <div class="grid">
    <section class="card hero span-2">
      <h2>Bereitschaft <span class="small">${esc(fmtDate(d.date, { weekday: "short", day: "numeric", month: "short" }))}</span></h2>
      <div class="score">${ring(r.score)}
        <div style="flex:1;min-width:0">
          <div class="level">${esc(r.label)}</div>
          <div class="small" style="color:#BDBDB5">Ab 80 voll belastbar, unter 50 Trainingslast reduzieren.</div>
          <div class="bars">${compRows}</div>
        </div>
      </div>
      ${r.notes?.length ? `<ul class="notes">${r.notes.map((x) => `<li>${esc(x)}</li>`).join("")}</ul>` : ""}
    </section>

    <section class="card">
      <h2>Morgenroutine</h2>
      <ul class="checks">${d.ritual.map((x) => `<li><span class="tick ${x.done ? "on" : ""}"></span>${esc(x.label)}</li>`).join("")}</ul>
      <div class="row" style="margin-top:14px"><a class="btn btn-small" href="#journal">Journal öffnen</a></div>
    </section>

    <section class="card hero span-2">
      <h2>Coaching-Briefing <span class="chip ${d.briefing.source === "claude" ? "y" : ""}">${d.briefing.source === "claude" ? "KI-Coach" : "Regeln"}</span></h2>
      <div class="briefing">${esc(d.briefing.text)}</div>
      <div class="row" style="margin-top:14px">
        <button class="btn btn-small" id="brief">${d.coach_enabled ? "KI-Briefing erstellen" : "Briefing aktualisieren"}</button>
        <button class="btn btn-ghost btn-small" id="read" style="color:#F5F5F2;border-color:#3A3A3A">Gelesen</button>
      </div>
    </section>

    <section class="card">
      <h2>Garmin heute</h2>
      <div class="kpis">
        <div class="kpi"><b>${num(m.sleep_hours, 1)}</b><span>Std. Schlaf</span></div>
        <div class="kpi"><b>${num(m.sleep_score)}</b><span>Schlafscore</span></div>
        <div class="kpi"><b>${num(m.hrv_ms)}</b><span>HRV ms</span></div>
        <div class="kpi"><b>${num(m.resting_hr)}</b><span>Ruhepuls</span></div>
        <div class="kpi"><b>${num(m.body_battery)}</b><span>Body Battery</span></div>
        <div class="kpi"><b>${num(m.steps)}</b><span>Schritte</span></div>
      </div>
    </section>

    <section class="card span-2">
      <h2>Training heute <a class="small" href="#woche">Woche ›</a></h2>
      ${d.today.length ? d.today.map((s) => sessionCard(s, { actions: true })).join("")
        : `<div class="empty-state"><img src="/static/icons/logo.svg" alt=""><div>Nichts geplant. Unter „Woche“ den Coach planen lassen.</div></div>`}
    </section>

    <section class="card">
      <h2>Wochenziele</h2>
      ${d.week_goals.map((g) => `<div class="goal"><div class="spread"><span>${esc(g.label)}</span><b>${g.done}/${g.goal}</b></div>
        <div class="pips">${Array.from({ length: Math.max(g.goal, g.done) }, (_, i) => `<i class="${i < g.done ? "on" : ""}"></i>`).join("")}</div></div>`).join("")}
    </section>

    <section class="card span-2">
      <h2>Streaks <span class="small">letzte 28 Tage</span></h2>
      ${d.streaks.habits.map((h) => `<div class="streak-row"><span>${esc(h.label)}</span>
        <div class="streak-cells">${h.days.map((v, i) => `<i class="${v ? "on" : ""}" title="${d.streaks.dates[i]}"></i>`).join("")}</div>
        <b>${h.streak}</b></div>`).join("")}
      <p class="small muted" style="margin:4px 0 0">Zahl rechts: Tage in Folge.</p>
    </section>

    <section class="card">
      <h2>Bereitschaft 14 Tage</h2>${spark(d.trend)}
    </section>

    <section class="card">
      <h2>Ausdauer & Zone 2</h2>
      <div class="kpis">
        <div class="kpi"><b>${run.zone2_hr ? run.zone2_hr.join("–") : "–"}</b><span>Zone-2-Puls</span></div>
        <div class="kpi"><b>${marches.count ?? 0}</b><span>Märsche 4 Wo.</span></div>
        <div class="kpi"><b>${marches.total_km ? num(marches.total_km, 1) : "–"}</b><span>km Marsch</span></div>
        <div class="kpi"><b>${marches.longest_km ? num(marches.longest_km, 1) : "–"}</b><span>längster km</span></div>
      </div>
      ${run.zone2_pace ? `<p class="small muted" style="margin:10px 0 0">Zone-2-Lauftempo: ${esc(run.zone2_pace)} (${esc(run.method)})</p>` : ""}
    </section>

    <section class="card">
      <h2>Ernährung <span class="chip">${n ? (n.mode === "jan" ? "Jan-Formel" : "Mifflin-St Jeor") : ""}</span></h2>
      ${n ? `<div class="kpis">
          <div class="kpi"><b>${num(n.kcal)}</b><span>kcal</span></div>
          <div class="kpi"><b>${num(n.protein_g)} g</b><span>Protein</span></div>
          <div class="kpi"><b>${num(n.carbs_g)} g</b><span>Kohlenhydrate</span></div>
          <div class="kpi"><b>${num(n.fat_g)} g</b><span>Fett</span></div>
          <div class="kpi"><b>${num(n.fiber_g)} g</b><span>Ballaststoffe</span></div>
          <div class="kpi"><b>${num(n.water_l, 1)} l</b><span>Wasser</span></div>
        </div>
        <div class="macro"><i style="width:${n.protein_pct}%"></i><i style="width:${n.carbs_pct}%"></i><i style="width:${n.fat_pct}%"></i></div>
        <div class="legend"><span>Protein ${n.protein_pct} %</span><span>KH ${n.carbs_pct} %</span><span>Fett ${n.fat_pct} %</span></div>
        ${n.bmr ? `<p class="small muted" style="margin:8px 0 0">Grundumsatz ${num(n.bmr)} kcal × PAL ${num(n.pal, 2)} · Ziel: ${esc(n.goal)}</p>` : ""}
        ${(n.hints || []).map((h) => `<div class="hint">${esc(h)}</div>`).join("")}`
      : '<p class="muted">Gewicht im Journal eintragen, dann berechne ich deinen Bedarf.</p>'}
    </section>

    <section class="card">
      <h2>Letzte Aktivitäten</h2>
      ${d.activities.length ? `<ul class="acts">${d.activities.map((a) => `<li><span><b>${esc(a.name || KIND_LABEL[a.kind])}</b><br><span class="small muted">${esc(fmtDate(a.date, { weekday: "short", day: "numeric", month: "short" }))} · ${esc(KIND_LABEL[a.kind] || a.kind)}</span></span>
        <span class="small" style="text-align:right">${dur(a.duration_s)}<br><span class="muted">${[km(a.distance_m), a.avg_hr ? "Ø " + Math.round(a.avg_hr) + " bpm" : ""].filter(Boolean).join(" · ")}</span></span></li>`).join("")}</ul>`
      : '<p class="muted">Noch keine Aktivitäten. Sync drücken oder FIT-Dateien unter „Daten“ importieren.</p>'}
    </section>
  </div>`;

  $("#prev").onclick = () => { state.day = addDays(state.day, -1); renderHeute(); };
  $("#next").onclick = () => { state.day = addDays(state.day, 1); renderHeute(); };
  $("#brief").onclick = async (e) => {
    e.target.disabled = true; e.target.textContent = "Coach denkt nach …";
    try { await api(`/api/briefing?day=${state.day}`, { method: "POST" }); renderHeute(); }
    catch (err) { toast(err.message, true); e.target.disabled = false; }
  };
  $("#read").onclick = async () => {
    await api(`/api/journal/${state.day}`, { method: "PUT", json: { briefing_read: true } });
    toast("Briefing als gelesen markiert"); renderHeute();
  };
  bindSessionActions(view, renderHeute);
}

/* ---------- Woche ---------- */
async function renderWoche() {
  state.weekStart = state.weekStart || mondayOf(isoToday());
  view.innerHTML = '<div class="loading">Lade Woche …</div>';
  const [w, chat] = await Promise.all([api(`/api/week?start=${state.weekStart}`), api(`/api/week/chat?start=${state.weekStart}`)]);
  const days = Array.from({ length: 7 }, (_, i) => addDays(w.week_start, i));
  const note = w.note;
  const kw = weekNumber(w.week_start);
  const feed = `${location.origin}/calendar.ics${token() ? "?token=" + encodeURIComponent(token()) : ""}`;

  view.innerHTML = `
  <div class="datebar">
    <button class="btn btn-ghost btn-small" id="prev" aria-label="Vorwoche">‹</button>
    <h1>KW ${kw} <span class="muted small" style="font-weight:400">${esc(fmtDate(days[0], { day: "numeric", month: "short" }))} – ${esc(fmtDate(days[6], { day: "numeric", month: "short" }))}</span></h1>
    <button class="btn btn-ghost btn-small" id="next" aria-label="Folgewoche">›</button>
  </div>
  <div class="grid" style="margin-bottom:14px">
    <section class="card hero span-2">
      <h2>Coach zur Woche ${note ? `<span class="chip y">${esc(note.phase)}</span>` : ""}</h2>
      ${note ? `<p style="margin:0 0 8px;font-weight:700">${esc(note.summary)}</p>
        <p class="small" style="margin:0;color:#CFCFC8">${esc(note.rationale)}</p>
        ${note.questions?.length ? `<ul class="notes">${note.questions.map((q) => `<li>${esc(q)}</li>`).join("")}</ul>` : ""}`
      : '<p style="margin:0">Für diese Woche gibt es noch keinen Plan.</p>'}
      <div class="row" style="margin-top:14px">
        <button class="btn" id="plan">${note ? "Neu planen" : "Trainingswoche planen"}</button>
      </div>
    </section>
    <section class="card">
      <h2>In Kalender übertragen</h2>
      <p class="small muted" style="margin-top:0">Abonniere diese Adresse einmal in Google Kalender (Weitere Kalender → Per URL). Neue Pläne erscheinen dann automatisch.</p>
      <code id="feed">${esc(feed)}</code>
      <div class="row" style="margin-top:10px"><button class="btn btn-small" id="copy">Adresse kopieren</button></div>
      ${w.busy_configured ? "" : '<p class="small muted">Tipp: Unter „Daten“ deine Kalender-Adresse hinterlegen, dann plant der Coach um deine Termine herum.</p>'}
    </section>
  </div>
  <div class="week">${days.map((d, i) => {
    const ss = w.sessions.filter((s) => s.date === d);
    const acts = w.activities.filter((a) => a.date === d);
    return `<div class="day ${d === isoToday() ? "today" : ""}"><h3><span>${WEEKDAYS[i]} ${new Date(d + "T12:00").getDate()}.</span>${d === isoToday() ? '<span class="chip y">heute</span>' : ""}</h3>
      ${ss.length ? ss.map((s) => sessionCard(s, { compact: true })).join("") : '<div class="empty">Ruhetag</div>'}
      ${acts.map((a) => `<div class="done-act">${esc(a.name || KIND_LABEL[a.kind])} ${dur(a.duration_s)}</div>`).join("")}</div>`;
  }).join("")}</div>
  <section class="card" style="margin-top:14px">
    <h2>Plan mit dem Coach anpassen</h2>
    <div class="chat" id="chat">${chat.history.map((h) => `<div class="msg ${h.role}">${esc(h.content)}</div>`).join("") || '<p class="muted small">Zum Beispiel: „Montag habe ich abends einen Termin, verschieb das Training.“ oder „Knie zwickt, diese Woche ohne Step-ups.“</p>'}</div>
    <form class="chat-form" id="chatForm"><textarea name="m" placeholder="Was soll der Coach ändern?" required></textarea><button class="btn">Senden</button></form>
  </section>`;

  $("#prev").onclick = () => { state.weekStart = addDays(state.weekStart, -7); renderWoche(); };
  $("#next").onclick = () => { state.weekStart = addDays(state.weekStart, 7); renderWoche(); };
  $("#copy").onclick = async () => { try { await navigator.clipboard.writeText(feed); toast("Adresse kopiert"); } catch { toast("Kopieren nicht möglich", true); } };
  $("#plan").onclick = async (e) => {
    e.target.disabled = true; e.target.textContent = "Coach plant deine Woche …";
    try { await api(`/api/week/plan?start=${state.weekStart}`, { method: "POST" }); toast("Woche geplant"); renderWoche(); }
    catch (err) { toast(err.message, true); e.target.disabled = false; }
  };
  view.querySelectorAll(".day .session").forEach((el) => el.addEventListener("click", () => {
    const s = w.sessions.find((x) => String(x.id) === el.dataset.id);
    const parent = el.parentElement;
    el.outerHTML = sessionCard(s, { actions: true });
    bindSessionActions(parent, renderWoche);
  }, { once: true }));
  $("#chatForm").onsubmit = async (e) => {
    e.preventDefault();
    const ta = e.target.m, msg = ta.value.trim(); if (!msg) return;
    const btn = e.target.querySelector("button"); btn.disabled = true; btn.textContent = "…";
    try { await api(`/api/week/chat?start=${state.weekStart}`, { method: "POST", json: { message: msg } }); renderWoche(); }
    catch (err) { toast(err.message, true); btn.disabled = false; btn.textContent = "Senden"; }
  };
}
function weekNumber(iso) {
  const d = new Date(iso + "T12:00:00"); d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7));
  const w1 = new Date(d.getFullYear(), 0, 4);
  return 1 + Math.round(((d - w1) / 86400000 - 3 + ((w1.getDay() + 6) % 7)) / 7);
}

/* ---------- Journal ---------- */
const FEEL = [["mood", "Stimmung"], ["energy", "Energie"], ["motivation", "Motivation"], ["soreness", "Muskelkater"], ["stress", "Stress"]];
async function renderJournal() {
  view.innerHTML = '<div class="loading">Lade Journal …</div>';
  const d = await api(`/api/journal/${state.day}`);
  const j = d.journal || {}, m = d.metrics || {}, c = j.corrections || {};
  const isToday = state.day === isoToday();
  view.innerHTML = `
  <div class="datebar">
    <button class="btn btn-ghost btn-small" id="prev" aria-label="Vortag">‹</button>
    <h1>${isToday ? "Journal heute" : esc(fmtDate(state.day))}</h1>
    <button class="btn btn-ghost btn-small" id="next" aria-label="Folgetag" ${isToday ? "disabled" : ""}>›</button>
  </div>
  <form id="jf" class="grid">
    <section class="card">
      <h2>Wie fühlst du dich? <span class="chip y">Score ${d.readiness.score ?? "–"}</span></h2>
      ${FEEL.map(([k, l]) => `<div class="slider"><label for="f-${k}">${l}</label>
        <input type="range" id="f-${k}" name="${k}" min="1" max="10" value="${j[k] ?? 5}" data-set="${j[k] != null}">
        <output>${j[k] ?? "–"}</output></div>`).join("")}
      <p class="small muted">1 = sehr schlecht / sehr wenig, 10 = sehr gut / sehr viel. Muskelkater und Stress zählen umgekehrt.</p>
    </section>
    <section class="card">
      <h2>Körper & Notizen</h2>
      <div class="fields"><label class="field">Gewicht (kg)<input type="number" step="0.1" name="weight_kg" value="${j.weight_kg ?? ""}"></label></div>
      <label class="field" style="margin-top:12px">Notizen für den Coach<textarea name="notes" placeholder="z. B. Knie heute ruhig, schlecht geschlafen wegen …">${esc(j.notes || "")}</textarea></label>
      <details style="margin-top:12px"><summary>Garmin-Werte korrigieren</summary>
        <div class="fields" style="margin-top:8px">
          ${[["sleep_hours", "Schlaf (h)", m.sleep_hours], ["hrv_ms", "HRV (ms)", m.hrv_ms], ["resting_hr", "Ruhepuls", m.resting_hr], ["body_battery", "Body Battery", m.body_battery]]
            .map(([k, l, g]) => `<label class="field">${l}<input type="number" step="0.1" data-corr="${k}" value="${c[k] ?? ""}" placeholder="Garmin: ${g ?? "–"}"></label>`).join("")}
        </div></details>
    </section>
    <section class="card">
      <h2>Food Memory</h2>
      <div class="slider"><label for="f-food">Ernährung</label><input type="range" id="f-food" name="food_quality" min="1" max="5" value="${j.food_quality ?? 3}" data-set="${j.food_quality != null}"><output>${j.food_quality ?? "–"}</output></div>
      <label class="field" style="margin-top:12px">Was hast du gegessen?<textarea name="food_notes" placeholder="Kein Kalorienzählen, nur grob: Frühstück, Mittag, Abend, Snacks, Alkohol …">${esc(j.food_notes || "")}</textarea></label>
      <p class="small muted">1 = ungesund, 5 = sehr gut. Der Coach nutzt das, um gute und schlechte Tage zu erklären.</p>
    </section>
    <section class="card span-2">
      <h2>Trainings an diesem Tag</h2>
      ${d.activities.length ? d.activities.map((a) => `<div class="session kind-${esc(a.kind)}" data-act="${esc(a.id)}">
        <div class="spread"><h3>${esc(a.name || KIND_LABEL[a.kind])}</h3><span class="small muted">${dur(a.duration_s)} ${km(a.distance_m)}</span></div>
        <div class="fields" style="margin-top:10px">
          <label class="field">Anstrengung (RPE 1–10)<input type="number" min="1" max="10" name="rpe" value="${a.rpe ?? ""}"></label>
          <label class="field" style="grid-column:span 2">Wie war's?<input type="text" name="feedback" value="${esc(a.feedback || "")}" placeholder="z. B. Swings schwer, Knie ok"></label>
        </div></div>`).join("") : '<p class="muted">Keine Aktivitäten von Garmin für diesen Tag.</p>'}
    </section>
    <div class="span-all row"><button class="btn" type="submit">Speichern</button></div>
  </form>`;

  $("#prev").onclick = () => { state.day = addDays(state.day, -1); renderJournal(); };
  $("#next").onclick = () => { state.day = addDays(state.day, 1); renderJournal(); };
  view.querySelectorAll('input[type="range"]').forEach((r) => r.addEventListener("input", () => { r.dataset.set = "true"; r.nextElementSibling.textContent = r.value; }));
  $("#jf").onsubmit = async (e) => {
    e.preventDefault();
    const f = e.target, body = { corrections: {} };
    f.querySelectorAll('input[type="range"]').forEach((r) => { if (r.dataset.set === "true") body[r.name] = Number(r.value); });
    const w = f.weight_kg.value; if (w) body.weight_kg = Number(w);
    body.notes = f.notes.value; body.food_notes = f.food_notes.value;
    f.querySelectorAll("[data-corr]").forEach((i) => { body.corrections[i.dataset.corr] = i.value ? Number(i.value) : null; });
    try {
      await api(`/api/journal/${state.day}`, { method: "PUT", json: body });
      for (const el of f.querySelectorAll("[data-act]")) {
        const rpe = el.querySelector('[name="rpe"]').value, fb = el.querySelector('[name="feedback"]').value;
        await api(`/api/activities/${encodeURIComponent(el.dataset.act)}/feedback`, { method: "PUT", json: { rpe: rpe ? Number(rpe) : null, feedback: fb || null } });
      }
      toast("Journal gespeichert"); renderJournal();
    } catch (err) { toast(err.message, true); }
  };
}

/* ---------- Coach ---------- */
async function renderCoach() {
  view.innerHTML = '<div class="loading">Lade Chat …</div>';
  const [c, h] = await Promise.all([api("/api/chat"), api("/api/health")]);
  view.innerHTML = `<section class="card">
    <h2>Frag deinen Coach ${h.coach ? '<span class="chip y">KI aktiv</span>' : '<span class="chip">KI aus</span>'}</h2>
    <div class="chat" id="chat">${c.history.map((m) => `<div class="msg ${m.role}">${esc(m.content)}</div>`).join("")
      || '<p class="muted small">Fragen zu Training, Scores oder Ernährung. Zum Beispiel: „Warum ist mein Score heute niedrig?“ oder „Welche Kettlebell-Übungen ersetzen Kniebeugen, wenn das Knie zwickt?“</p>'}</div>
    <form class="chat-form" id="cf"><textarea name="m" placeholder="Nachricht an den Coach" required></textarea><button class="btn">Senden</button></form>
  </section>`;
  const chat = $("#chat"); chat.scrollTop = chat.scrollHeight;
  $("#cf").onsubmit = async (e) => {
    e.preventDefault();
    const msg = e.target.m.value.trim(); if (!msg) return;
    chat.insertAdjacentHTML("beforeend", `<div class="msg user">${esc(msg)}</div><div class="msg assistant muted" id="typing">Coach schreibt …</div>`);
    chat.scrollTop = chat.scrollHeight; e.target.m.value = "";
    try { await api("/api/chat", { method: "POST", json: { message: msg } }); renderCoach(); }
    catch (err) { $("#typing").textContent = err.message; }
  };
}

/* ---------- Daten & Einstellungen ---------- */
async function renderDaten() {
  view.innerHTML = '<div class="loading">Lade Einstellungen …</div>';
  const [s, h] = await Promise.all([api("/api/settings"), api("/api/health")]);
  const p = s.profile || {}, g = s.goals || {};
  const slotRows = WEEKDAYS.map((wd, i) => {
    const sl = (s.slots || {})[String(i)] || [];
    return `<div class="row small" style="margin-bottom:6px"><b style="width:28px">${wd}</b>${[0, 1].map((k) => `
      <input type="time" data-slot="${i}-${k}-0" value="${sl[k]?.[0] || ""}" style="width:auto">–<input type="time" data-slot="${i}-${k}-1" value="${sl[k]?.[1] || ""}" style="width:auto">`).join('<span class="muted">und</span>')}</div>`;
  }).join("");
  view.innerHTML = `<div class="grid">
    <section class="card">
      <h2>Garmin</h2>
      <p class="small" style="margin-top:0">Quelle: <b>${esc(h.source || "keine Live-Verbindung")}</b></p>
      <div class="row"><button class="btn btn-small" id="sync30">Letzte 30 Tage laden</button></div>
      <div class="drop" id="drop" style="margin-top:14px">FIT-Dateien, Garmin-Export (ZIP) oder Schlaf-/UDS-JSON hier ablegen<br>
        <label class="btn btn-ghost btn-small" style="margin-top:10px">Dateien wählen<input type="file" id="files" multiple accept=".fit,.zip,.json" hidden></label></div>
      <p class="small muted">FIT-Dateien findest du auf der Uhr per USB im Ordner GARMIN/Activity.</p>
    </section>
    <form class="card span-2" id="sf">
      <h2>Profil & Ernährung</h2>
      <div class="fields">
        <label class="field">Geschlecht<select name="sex"><option value="">–</option><option value="m" ${p.sex === "m" ? "selected" : ""}>männlich</option><option value="w" ${p.sex === "w" ? "selected" : ""}>weiblich</option></select></label>
        <label class="field">Größe (cm)<input type="number" name="height_cm" value="${p.height_cm ?? ""}"></label>
        <label class="field">Geburtsjahr<input type="number" name="birth_year" value="${p.birth_year ?? ""}"></label>
        <label class="field">Startgewicht (kg)<input type="number" step="0.1" name="weight_kg" value="${p.weight_kg ?? ""}"></label>
        <label class="field">Ziel<select name="goal">${["abnehmen", "halten", "aufbauen"].map((x) => `<option ${p.goal === x ? "selected" : ""}>${x}</option>`).join("")}</select></label>
        <label class="field">Rechner<select name="nutrition_mode"><option value="wissenschaft" ${p.nutrition_mode !== "jan" ? "selected" : ""}>Wissenschaftlich (Mifflin-St Jeor)</option><option value="jan" ${p.nutrition_mode === "jan" ? "selected" : ""}>Jan-Formel (Excel)</option></select></label>
      </div>
      <h2 style="margin:18px 0 12px">Training</h2>
      <div class="fields">
        <label class="field">Functional/Kraft pro Woche<input type="number" min="0" max="6" name="g_strength" value="${g.strength ?? 0}"></label>
        <label class="field">Ausdauer (Laufband) pro Woche<input type="number" min="0" max="6" name="g_cardio" value="${g.cardio ?? 0}"></label>
        <label class="field">Lange Märsche pro Woche<input type="number" min="0" max="2" name="g_march" value="${g.march ?? g.longrun ?? 0}"></label>
        <label class="field">Maximalpuls<input type="number" name="max_hr" value="${s.max_hr ?? 190}"></label>
        <label class="field">Schlafziel (h)<input type="number" step="0.5" name="sleep_target_h" value="${s.sleep_target_h ?? 8}"></label>
      </div>
      <label class="field" style="margin-top:12px">Vorlieben<textarea name="preferences">${esc(s.preferences || "")}</textarea></label>
      <label class="field" style="margin-top:12px">Einschränkungen<textarea name="constraints">${esc(s.constraints || "")}</textarea></label>
      <label class="field" style="margin-top:12px">Ziel (Ausdauer)<input type="text" name="running_goal" value="${esc(s.running_goal || "")}"></label>
      <h2 style="margin:18px 0 12px">Freie Trainingsfenster</h2>${slotRows}
      <label class="field" style="margin-top:12px">Privatadresse deines Kalenders im iCal-Format (für Terminlücken)<input type="url" name="busy_ics_url" value="${esc(s.busy_ics_url || "")}" placeholder="https://calendar.google.com/calendar/ical/…/basic.ics"></label>
      <div class="row" style="margin-top:16px"><button class="btn">Einstellungen speichern</button></div>
    </form>
    <section class="card">
      <h2>App</h2>
      <p class="small">Version ${esc(h.version)} · KI-Coach: ${h.coach ? "aktiv" : "aus (ANTHROPIC_API_KEY fehlt)"} · Zugangsschutz: ${h.auth ? "an" : "aus"}</p>
      <div class="row"><button class="btn btn-ghost btn-small" id="tok">Zugangscode eingeben</button></div>
    </section>
  </div>`;

  $("#sync30").onclick = async (e) => { e.target.disabled = true; try { const r = await api("/api/sync?days=30", { method: "POST" }); toast(r.message, !r.ok); } catch (err) { toast(err.message, true); } e.target.disabled = false; };
  $("#tok").onclick = askToken;
  const upload = async (files) => {
    if (!files.length) return;
    const fd = new FormData(); [...files].forEach((f) => fd.append("files", f));
    try { const r = await api("/api/import", { method: "POST", body: fd }); toast(r.message + (r.errors?.length ? ` (${r.errors.length} Fehler)` : ""), !r.ok); }
    catch (err) { toast(err.message, true); }
  };
  $("#files").onchange = (e) => upload(e.target.files);
  const drop = $("#drop");
  ["dragenter", "dragover"].forEach((t) => drop.addEventListener(t, (e) => { e.preventDefault(); drop.classList.add("over"); }));
  ["dragleave", "drop"].forEach((t) => drop.addEventListener(t, (e) => { e.preventDefault(); drop.classList.remove("over"); }));
  drop.addEventListener("drop", (e) => upload(e.dataTransfer.files));

  $("#sf").onsubmit = async (e) => {
    e.preventDefault();
    const f = e.target, n = (v) => (v === "" ? null : Number(v));
    const slots = {};
    for (let i = 0; i < 7; i++) {
      slots[i] = [0, 1].map((k) => [f.querySelector(`[data-slot="${i}-${k}-0"]`).value, f.querySelector(`[data-slot="${i}-${k}-1"]`).value]).filter(([a, b]) => a && b && a < b);
    }
    const body = {
      profile: { sex: f.sex.value || null, height_cm: n(f.height_cm.value), birth_year: n(f.birth_year.value), weight_kg: n(f.weight_kg.value), goal: f.goal.value, nutrition_mode: f.nutrition_mode.value },
      goals: { strength: n(f.g_strength.value) ?? 0, cardio: n(f.g_cardio.value) ?? 0, march: n(f.g_march.value) ?? 0 },
      max_hr: n(f.max_hr.value), sleep_target_h: n(f.sleep_target_h.value),
      preferences: f.preferences.value, constraints: f.constraints.value, running_goal: f.running_goal.value,
      busy_ics_url: f.busy_ics_url.value.trim(), slots,
    };
    try { await api("/api/settings", { method: "PUT", json: body }); toast("Gespeichert"); } catch (err) { toast(err.message, true); }
  };
}

/* ---------- Router ---------- */
const ROUTES = { heute: renderHeute, woche: renderWoche, journal: renderJournal, coach: renderCoach, daten: renderDaten };
async function route() {
  const tab = (location.hash || "#heute").slice(1);
  const fn = ROUTES[tab] || renderHeute;
  document.querySelectorAll(".tabs a").forEach((a) => a.classList.toggle("active", a.dataset.tab === (ROUTES[tab] ? tab : "heute")));
  try { await fn(); } catch (e) {
    view.innerHTML = `<div class="card"><h2>Fehler</h2><p>${esc(e.message)}</p><button class="btn btn-small" onclick="location.reload()">Neu laden</button></div>`;
  }
}
window.addEventListener("hashchange", () => { window.scrollTo(0, 0); route(); });
route();
if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
