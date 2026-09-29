import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import { getAuth, getIdTokenResult, onAuthStateChanged, signInWithEmailAndPassword, signOut } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";
import { getFunctions, httpsCallable } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-functions.js";

const firebaseConfig = {
  apiKey: "AIzaSyBQfe36JwUXD4-Xq9_ky2IQD3mLwOORUhk",
  authDomain: "alpha-ride-29708.firebaseapp.com",
  projectId: "alpha-ride-29708",
  storageBucket: "alpha-ride-29708.firebasestorage.app",
  messagingSenderId: "486103357366",
  appId: "1:486103357366:web:98c3bd6fd18719067f1317",
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const functions = getFunctions(app, "africa-south1");
const call = (name) => httpsCallable(functions, name);
const api = {
  overview: call("adminGetOperationsOverview"),
  drivers: call("adminListDrivers"),
  rides: call("adminListRides"),
  activity: call("adminListAdminActivity"),
  creditWallet: call("adminCreditDriverWallet"),
  walletStatus: call("adminSetDriverWalletStatus"),
  reviewStatus: call("adminSetDriverReviewStatus"),
  vehicleClass: call("adminSetDriverVehicleClass"),
  transactions: call("adminListWalletTransactions"),
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const el = {
  loginView: $("#login-view"), adminView: $("#admin-view"), loginForm: $("#login-form"), loginError: $("#login-error"),
  email: $("#email"), password: $("#password"), adminEmail: $("#admin-email"), daypart: $("#daypart"), pendingNav: $("#pending-nav-count"),
  overviewStats: $("#overview-stats"), attention: $("#attention-list"), rideBreakdown: $("#ride-breakdown"), refreshOverview: $("#refresh-overview"),
  refreshDrivers: $("#refresh-drivers"), driverSearch: $("#driver-search"), driverFilter: $("#driver-filter"), driverCount: $("#driver-count"), driverList: $("#driver-list"),
  empty: $("#empty-state"), detail: $("#driver-detail"), name: $("#driver-name"), meta: $("#driver-meta"), reviewBadge: $("#review-badge"),
  walletBalance: $("#wallet-balance"), walletStatus: $("#wallet-status"), walletCredits: $("#wallet-credits"), walletDebits: $("#wallet-debits"),
  vehicleType: $("#vehicle-type"), plateNumber: $("#plate-number"), vehicleClass: $("#vehicle-class"), vehicleClassHint: $("#vehicle-class-hint"), saveVehicleClass: $("#save-vehicle-class"),
  topupForm: $("#topup-form"), topupAmount: $("#topup-amount"), topupReference: $("#topup-reference"), topupNote: $("#topup-note"), rechargePreview: $("#recharge-preview"),
  reviewStatus: $("#review-status"), saveReview: $("#save-review"), walletStatusSelect: $("#wallet-status-select"), saveWalletStatus: $("#save-wallet-status"), ledger: $("#ledger-body"),
  refreshRides: $("#refresh-rides"), rideSearch: $("#ride-search"), rideFilter: $("#ride-filter"), rideCount: $("#ride-count"), ridesBody: $("#rides-body"),
  refreshActivity: $("#refresh-activity"), activityBody: $("#activity-body"), toast: $("#toast"), dialog: $("#confirm-dialog"),
  confirmTitle: $("#confirm-title"), confirmMessage: $("#confirm-message"), confirmCancel: $("#confirm-cancel"), confirmAccept: $("#confirm-accept"),
};

let drivers = [];
let rides = [];
let selectedDriverId = null;
let toastTimer = null;
let confirmResolver = null;

const money = (value) => new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(Number.isFinite(Number(value)) ? Number(value) : 0);
const compact = (value) => new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 }).format(Number(value) || 0);
const dateTime = (millis) => millis ? new Date(millis).toLocaleString([], { dateStyle: "medium", timeStyle: "short" }) : "Pending";
const readableError = (error) => (typeof error?.message === "string" ? error.message : "")
  .replace(/^Firebase:\s*/i, "").replace(/^Functions:\s*/i, "").replace(/\s*\([^)]*\)\.?$/, "").trim() || "The operation could not be completed.";
const vehicleClassLabel = (value) => ({ boda: "Boda", rickshaw: "Rickshaw", standard: "Standard", comfort: "Comfort", ev: "Electric", premium: "Premium", corporate: "Corporate" })[value] || "Unassigned";
const activeStatuses = new Set(["requested", "offered", "accepted", "driver_arriving", "arrived", "in_progress"]);

function showToast(message, tone = "success") {
  clearTimeout(toastTimer); el.toast.textContent = message; el.toast.dataset.tone = tone; el.toast.hidden = false;
  toastTimer = setTimeout(() => { el.toast.hidden = true; }, 4500);
}

function setBusy(button, busy, label = "Working…") {
  button.disabled = busy; button.dataset.originalText ??= button.textContent; button.textContent = busy ? label : button.dataset.originalText;
}

function confirmAction({ title, message, confirmLabel = "Confirm" }) {
  if (confirmResolver) confirmResolver(false);
  el.confirmTitle.textContent = title; el.confirmMessage.textContent = message; el.confirmAccept.textContent = confirmLabel; el.dialog.hidden = false;
  requestAnimationFrame(() => el.confirmAccept.focus());
  return new Promise((resolve) => { confirmResolver = resolve; });
}

function closeDialog(result) {
  el.dialog.hidden = true; const resolve = confirmResolver; confirmResolver = null; resolve?.(result);
}

function navigate(view) {
  $$("[data-page]").forEach((page) => page.classList.toggle("active", page.dataset.page === view));
  $$("[data-view]").forEach((button) => button.classList.toggle("active", button.dataset.view === view));
  window.scrollTo({ top: 0, behavior: "smooth" });
  if (view === "rides" && rides.length === 0) loadRides();
  if (view === "activity") loadActivity();
}

function metricCard(label, value, hint, tone = "neutral") {
  const card = document.createElement("article"); card.className = `metric-card ${tone}`;
  const l = document.createElement("span"); l.textContent = label;
  const v = document.createElement("strong"); v.textContent = value;
  const h = document.createElement("small"); h.textContent = hint;
  card.append(l, v, h); return card;
}

function attentionItem(title, description, count, target, tone) {
  const button = document.createElement("button"); button.type = "button"; button.className = `attention-item ${tone}`;
  const copy = document.createElement("span"); const strong = document.createElement("strong"); strong.textContent = title;
  const small = document.createElement("small"); small.textContent = description; copy.append(strong, small);
  const badge = document.createElement("b"); badge.textContent = count; button.append(copy, badge); button.addEventListener("click", () => { if (target.filter) el.driverFilter.value = target.filter; navigate(target.view); renderDriverList(); });
  return button;
}

async function loadOverview() {
  setBusy(el.refreshOverview, true, "Refreshing…");
  try {
    const { data } = await api.overview(); const d = data.drivers || {}; const r = data.rides || {}; const m = data.money || {};
    el.overviewStats.replaceChildren(
      metricCard("Drivers", money(d.total), `${money(d.approved)} approved`, "green"),
      metricCard("Active rides", money(r.active), `${money(r.today)} requested today`, "blue"),
      metricCard("Wallet credit", `${compact(m.walletBalances)} SSP`, "Across driver wallets", "violet"),
      metricCard("Alpha fees", `${compact(m.lifetimeDebits)} SSP`, "Lifetime wallet deductions", "dark"),
    );
    el.pendingNav.textContent = d.pending || 0; el.pendingNav.hidden = !(d.pending > 0);
    el.attention.replaceChildren();
    const items = [
      ["Pending approvals", "Review driver documents and vehicle", d.pending, { view: "drivers", filter: "pending" }, "amber"],
      ["Wallet recharge needed", "Drivers at or below the low balance level", d.lowBalance, { view: "drivers", filter: "low" }, "red"],
      ["Vehicle class missing", "Regular cars waiting for classification", d.unclassified, { view: "drivers", filter: "unclassified" }, "blue"],
      ["Suspended wallets", "Accounts currently blocked from work", d.suspended, { view: "drivers", filter: "blocked" }, "neutral"],
    ];
    items.forEach((item) => el.attention.append(attentionItem(...item)));
    el.rideBreakdown.replaceChildren();
    [["Completed", r.completed, "green"], ["Active", r.active, "blue"], ["Cancelled", r.cancelled, "red"], ["Gross fare", `${money(r.grossFare)} SSP`, "dark"]].forEach(([label, value, tone]) => {
      const row = document.createElement("div"); row.className = "breakdown-row"; const labelEl = document.createElement("span"); labelEl.textContent = label; const valueEl = document.createElement("strong"); valueEl.className = tone; valueEl.textContent = value; row.append(labelEl, valueEl); el.rideBreakdown.append(row);
    });
  } catch (error) { showToast(readableError(error), "error"); }
  finally { setBusy(el.refreshOverview, false); }
}

function selectedDriver() { return drivers.find((driver) => driver.driverId === selectedDriverId) || null; }
function searchableDriver(driver) { return [driver.firstName, driver.lastName, driver.phoneNumber, driver.plateNumber, driver.vehicleType, driver.vehicleClass, driver.driverId].join(" ").toLowerCase(); }
function driverMatchesFilter(driver, filter) {
  const wallet = driver.wallet || {};
  return filter === "all" || (filter === "pending" && driver.reviewStatus === "pending") || (filter === "low" && wallet.isLowBalance) || (filter === "blocked" && wallet.status === "suspended") || (filter === "unclassified" && driver.requiresVehicleClass && !driver.vehicleClass);
}

function renderDriverList() {
  const query = el.driverSearch.value.trim().toLowerCase(); const filter = el.driverFilter.value;
  const filtered = drivers.filter((driver) => driverMatchesFilter(driver, filter) && (!query || searchableDriver(driver).includes(query)));
  el.driverCount.textContent = `${filtered.length} of ${drivers.length} drivers`; el.driverList.replaceChildren();
  for (const driver of filtered) {
    const button = document.createElement("button"); button.type = "button"; button.className = "driver-item"; if (driver.driverId === selectedDriverId) button.classList.add("selected");
    const top = document.createElement("span"); top.className = "driver-item-top"; const name = document.createElement("strong"); name.textContent = `${driver.firstName || ""} ${driver.lastName || ""}`.trim() || "Unnamed driver"; const status = document.createElement("em"); status.textContent = driver.reviewStatus || "pending"; status.dataset.status = driver.reviewStatus || "pending"; top.append(name, status);
    const details = document.createElement("span"); details.textContent = `${driver.phoneNumber || "No phone"} · ${money(driver.wallet?.balance)} SSP`;
    button.append(top, details); button.addEventListener("click", () => selectDriver(driver.driverId)); el.driverList.append(button);
  }
  if (!filtered.length) { const message = document.createElement("p"); message.className = "empty-list muted"; message.textContent = "No drivers match these filters."; el.driverList.append(message); }
}

async function loadDrivers({ preserveSelection = true } = {}) {
  setBusy(el.refreshDrivers, true, "Refreshing…");
  try {
    const result = await api.drivers({ limit: 200 }); drivers = Array.isArray(result.data?.drivers) ? result.data.drivers : [];
    if (!preserveSelection || (selectedDriverId && !selectedDriver())) selectedDriverId = null;
    renderDriverList(); renderDriverDetail(selectedDriver());
  } catch (error) { showToast(readableError(error), "error"); }
  finally { setBusy(el.refreshDrivers, false); }
}

async function selectDriver(driverId) { selectedDriverId = driverId; renderDriverList(); renderDriverDetail(selectedDriver()); await loadLedger(driverId); }

function renderDriverDetail(driver) {
  if (!driver) { el.empty.hidden = false; el.detail.hidden = true; return; }
  const wallet = driver.wallet || {}; el.empty.hidden = true; el.detail.hidden = false;
  el.name.textContent = `${driver.firstName || ""} ${driver.lastName || ""}`.trim() || "Unnamed driver";
  el.meta.textContent = `${driver.phoneNumber || "No phone"} · ${driver.driverId}`; el.reviewBadge.textContent = driver.reviewStatus || "pending"; el.reviewBadge.dataset.status = driver.reviewStatus || "pending";
  el.walletBalance.textContent = `${money(wallet.balance)} ${wallet.currencyCode || "SSP"}`;
  el.walletStatus.textContent = wallet.status === "suspended" ? "Suspended — cannot work" : wallet.balance <= 0 ? "Recharge required" : wallet.isLowBalance ? "Low balance" : "Ready for rides";
  el.walletCredits.textContent = `${money(wallet.lifetimeCredits)} SSP`; el.walletDebits.textContent = `${money(wallet.lifetimeDebits)} SSP`;
  el.vehicleType.textContent = driver.vehicleType || "Not recorded"; el.plateNumber.textContent = `${driver.plateNumber || "No plate"} · Alpha ${vehicleClassLabel(driver.vehicleClass)}`;
  el.vehicleClass.value = driver.vehicleClass || ""; el.vehicleClass.disabled = !driver.requiresVehicleClass; el.saveVehicleClass.disabled = !driver.requiresVehicleClass;
  el.vehicleClassHint.textContent = driver.requiresVehicleClass ? (driver.vehicleClass ? "Update only after inspecting the vehicle." : "Required before this vehicle can be approved.") : `Automatically classified as ${vehicleClassLabel(driver.vehicleClass)}.`;
  el.reviewStatus.value = driver.reviewStatus || "pending"; el.walletStatusSelect.value = wallet.status || "active"; updateRechargePreview();
}

function updateRechargePreview() {
  const driver = selectedDriver(); const amount = Number(el.topupAmount.value);
  el.rechargePreview.textContent = driver && Number.isFinite(amount) && amount > 0 ? `New balance: ${money((driver.wallet?.balance || 0) + amount)} SSP` : "Enter an amount to preview the new balance.";
}

function cellRow(values, classes = {}) {
  const row = document.createElement("tr"); values.forEach((value, index) => { const cell = document.createElement("td"); cell.textContent = value; if (classes[index]) cell.className = classes[index]; row.append(cell); }); return row;
}

async function loadLedger(driverId) {
  el.ledger.replaceChildren(cellRow(["Loading wallet history…"])); el.ledger.firstElementChild.firstElementChild.colSpan = 5;
  try {
    const result = await api.transactions({ driverId }); const txs = Array.isArray(result.data?.transactions) ? result.data.transactions : []; el.ledger.replaceChildren();
    if (!txs.length) { const row = cellRow(["No wallet transactions yet."]); row.firstElementChild.colSpan = 5; el.ledger.append(row); return; }
    txs.forEach((item) => { const credit = item.type === "top_up"; const type = item.type === "ride_fee" ? "Ride fee" : credit ? "Office recharge" : "Access change"; el.ledger.append(cellRow([dateTime(item.createdAtMillis), type, `${credit ? "+" : item.amount ? "−" : ""}${money(item.amount)} ${item.currencyCode || "SSP"}`, `${money(item.balanceAfter)} ${item.currencyCode || "SSP"}`, item.reference || item.rideId || item.note || "—"], { 2: item.amount ? (credit ? "credit" : "debit") : "" })); });
  } catch (error) { el.ledger.replaceChildren(); const row = cellRow([readableError(error)]); row.firstElementChild.colSpan = 5; el.ledger.append(row); }
}

function rideStatusLabel(status) { return ({ driver_arriving: "Driver arriving", in_progress: "In progress" })[status] || (status ? status[0].toUpperCase() + status.slice(1) : "Unknown"); }
function renderRides() {
  const query = el.rideSearch.value.trim().toLowerCase(); const filter = el.rideFilter.value;
  const filtered = rides.filter((ride) => {
    const statusMatch = filter === "all" || (filter === "active" && activeStatuses.has(ride.status)) || ride.status === filter;
    return statusMatch && (!query || [ride.rideId, ride.driverId, ride.passengerId, ride.status, ride.rideOptionId].join(" ").toLowerCase().includes(query));
  });
  el.rideCount.textContent = `${filtered.length} of ${rides.length} recent rides`; el.ridesBody.replaceChildren();
  filtered.forEach((ride) => el.ridesBody.append(cellRow([dateTime(ride.updatedAtMillis), ride.rideId.slice(0, 10), rideStatusLabel(ride.status), vehicleClassLabel(ride.rideOptionId), ride.driverName || (ride.driverId ? ride.driverId.slice(0, 10) : "Unassigned"), `${money(ride.finalFare || ride.estimatedFare)} SSP`, `${money(ride.platformFee)} SSP`], { 2: `status-cell status-${ride.status}` })));
  if (!filtered.length) { const row = cellRow(["No rides match these filters."]); row.firstElementChild.colSpan = 7; el.ridesBody.append(row); }
}

async function loadRides() {
  setBusy(el.refreshRides, true, "Refreshing…");
  try { const result = await api.rides({ limit: 150 }); rides = Array.isArray(result.data?.rides) ? result.data.rides : []; renderRides(); }
  catch (error) { showToast(readableError(error), "error"); }
  finally { setBusy(el.refreshRides, false); }
}

function activityLabel(action) { return ({ driver_review_status: "Driver review", driver_vehicle_class: "Vehicle class", wallet_top_up: "Wallet recharge", wallet_status: "Wallet access" })[action] || action.replaceAll("_", " "); }
async function loadActivity() {
  setBusy(el.refreshActivity, true, "Refreshing…"); el.activityBody.replaceChildren();
  try {
    const result = await api.activity({ limit: 150 }); const items = Array.isArray(result.data?.activity) ? result.data.activity : [];
    items.forEach((item) => el.activityBody.append(cellRow([dateTime(item.createdAtMillis), activityLabel(item.action), item.driverName || item.driverId?.slice(0, 12) || "—", item.summary || "—", item.administratorEmail || "Authorized admin"])));
    if (!items.length) { const row = cellRow(["No administrator activity yet."]); row.firstElementChild.colSpan = 5; el.activityBody.append(row); }
  } catch (error) { const row = cellRow([readableError(error)]); row.firstElementChild.colSpan = 5; el.activityBody.append(row); }
  finally { setBusy(el.refreshActivity, false); }
}

el.loginForm.addEventListener("submit", async (event) => { event.preventDefault(); el.loginError.textContent = ""; const button = el.loginForm.querySelector("button"); setBusy(button, true, "Signing in…"); try { await signInWithEmailAndPassword(auth, el.email.value.trim(), el.password.value); } catch (error) { el.loginError.textContent = readableError(error); } finally { setBusy(button, false); } });
[$("#sign-out"), $("#mobile-sign-out")].forEach((button) => button.addEventListener("click", () => signOut(auth)));
$$('[data-view]').forEach((button) => button.addEventListener("click", () => navigate(button.dataset.view)));
$$('.jump').forEach((button) => button.addEventListener("click", () => navigate(button.dataset.target)));
el.confirmCancel.addEventListener("click", () => closeDialog(false)); el.confirmAccept.addEventListener("click", () => closeDialog(true)); el.dialog.addEventListener("click", (event) => { if (event.target === el.dialog) closeDialog(false); });
document.addEventListener("keydown", (event) => { if (event.key === "Escape" && !el.dialog.hidden) closeDialog(false); });
el.refreshOverview.addEventListener("click", loadOverview); el.refreshDrivers.addEventListener("click", () => loadDrivers()); el.driverSearch.addEventListener("input", renderDriverList); el.driverFilter.addEventListener("change", renderDriverList);
el.refreshRides.addEventListener("click", loadRides); el.rideSearch.addEventListener("input", renderRides); el.rideFilter.addEventListener("change", renderRides); el.refreshActivity.addEventListener("click", loadActivity);
$$('.quick-amounts button').forEach((button) => button.addEventListener("click", () => { el.topupAmount.value = button.dataset.amount; updateRechargePreview(); })); el.topupAmount.addEventListener("input", updateRechargePreview);

el.topupForm.addEventListener("submit", async (event) => {
  event.preventDefault(); const driver = selectedDriver(); if (!driver) return; const amount = Number(el.topupAmount.value); const reference = el.topupReference.value.trim();
  const approved = await confirmAction({ title: "Confirm wallet recharge", message: `Add ${money(amount)} SSP to ${el.name.textContent}? The receipt reference is ${reference}. This creates a permanent audit record.`, confirmLabel: `Add ${money(amount)} SSP` }); if (!approved) return;
  const button = el.topupForm.querySelector("button[type=submit]"); setBusy(button, true, "Recording…");
  try { await api.creditWallet({ driverId: driver.driverId, amount, reference, note: el.topupNote.value.trim() }); el.topupForm.reset(); showToast("Wallet recharge recorded successfully."); await Promise.all([loadDrivers(), loadLedger(driver.driverId), loadOverview()]); }
  catch (error) { showToast(readableError(error), "error"); } finally { setBusy(button, false); updateRechargePreview(); }
});

el.saveVehicleClass.addEventListener("click", async () => { const driver = selectedDriver(); if (!driver?.requiresVehicleClass) return; if (!el.vehicleClass.value) return showToast("Select an Alpha ride class first.", "error"); const approved = await confirmAction({ title: "Change vehicle class?", message: `Assign ${el.name.textContent} to Alpha ${vehicleClassLabel(el.vehicleClass.value)} after physical inspection?`, confirmLabel: "Save class" }); if (!approved) return; setBusy(el.saveVehicleClass, true); try { await api.vehicleClass({ driverId: driver.driverId, vehicleClass: el.vehicleClass.value }); showToast("Driver vehicle class updated."); await Promise.all([loadDrivers(), loadOverview()]); } catch (error) { showToast(readableError(error), "error"); } finally { setBusy(el.saveVehicleClass, false); } });
el.saveReview.addEventListener("click", async () => { const driver = selectedDriver(); if (!driver) return; const status = el.reviewStatus.value; const approved = await confirmAction({ title: `${rideStatusLabel(status)} this driver?`, message: `Change ${el.name.textContent}'s review status to ${status}.`, confirmLabel: "Save status" }); if (!approved) return; setBusy(el.saveReview, true); try { await api.reviewStatus({ driverId: driver.driverId, reviewStatus: status, note: "Updated from Alpha Admin" }); showToast("Driver review status updated."); await Promise.all([loadDrivers(), loadOverview()]); } catch (error) { showToast(readableError(error), "error"); } finally { setBusy(el.saveReview, false); } });
el.saveWalletStatus.addEventListener("click", async () => { const driver = selectedDriver(); if (!driver) return; const status = el.walletStatusSelect.value; const approved = await confirmAction({ title: status === "suspended" ? "Suspend wallet access?" : "Restore wallet access?", message: status === "suspended" ? `${el.name.textContent} will be unable to go online or accept rides.` : `${el.name.textContent} may work again if the wallet has enough credit.`, confirmLabel: status === "suspended" ? "Suspend access" : "Restore access" }); if (!approved) return; setBusy(el.saveWalletStatus, true); try { await api.walletStatus({ driverId: driver.driverId, status, note: "Updated from Alpha Admin" }); showToast("Wallet access updated."); await Promise.all([loadDrivers(), loadLedger(driver.driverId), loadOverview()]); } catch (error) { showToast(readableError(error), "error"); } finally { setBusy(el.saveWalletStatus, false); } });

onAuthStateChanged(auth, async (user) => {
  if (!user) { el.loginView.hidden = false; el.adminView.hidden = true; el.password.value = ""; return; }
  try {
    const token = await getIdTokenResult(user, true); if (token.claims.admin !== true) { await signOut(auth); el.loginError.textContent = "This account is not authorized for Alpha administration."; return; }
    el.loginView.hidden = true; el.adminView.hidden = false; el.adminEmail.textContent = user.email || "Authorized administrator";
    const hour = new Date().getHours(); el.daypart.textContent = hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening";
    await Promise.all([loadOverview(), loadDrivers({ preserveSelection: false })]);
  } catch (error) { el.loginError.textContent = readableError(error); await signOut(auth); }
});
