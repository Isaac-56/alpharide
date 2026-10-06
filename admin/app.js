import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import { getAuth, getIdTokenResult, onAuthStateChanged, signInWithEmailAndPassword, signOut } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";
import { getFunctions, httpsCallable } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-functions.js";
import { getBlob, getStorage, ref as storageRef } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-storage.js";

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
const storage = getStorage(app);
const functions = getFunctions(app, "africa-south1");
const call = (name) => httpsCallable(functions, name);
const api = {
  overview: call("adminGetOperationsOverview"),
  drivers: call("adminListDrivers"),
  driverReview: call("adminGetDriverReview"),
  rides: call("adminListRides"),
  receipts: call("adminListReceipts"),
  recharges: call("adminListRecharges"),
  activity: call("adminListAdminActivity"),
  businessSettings: call("adminGetBusinessSettings"),
  setBusinessSettings: call("adminSetBusinessSettings"),
  commissionReport: call("adminGetCommissionReport"),
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
  vehicleType: $("#vehicle-type"), plateNumber: $("#plate-number"), vehicleClasses: $("#vehicle-classes"), vehicleClassHint: $("#vehicle-class-hint"), saveVehicleClass: $("#save-vehicle-class"),
  reviewStatus: $("#review-status"), saveReview: $("#save-review"), walletStatusSelect: $("#wallet-status-select"), saveWalletStatus: $("#save-wallet-status"), ledger: $("#ledger-body"),
  reviewNote: $("#review-note"), reviewReadiness: $("#review-readiness"), reviewChecklist: $("#review-checklist"),
  identityDetails: $("#identity-details"), vehicleDetails: $("#vehicle-details"), licenceDetails: $("#licence-details"),
  licenceFrontLink: $("#licence-front-link"), licenceFrontImage: $("#licence-front-image"), licenceFrontStatus: $("#licence-front-status"), licenceFrontPlaceholder: $("#licence-front-placeholder"),
  licenceBackLink: $("#licence-back-link"), licenceBackImage: $("#licence-back-image"), licenceBackStatus: $("#licence-back-status"), licenceBackPlaceholder: $("#licence-back-placeholder"),
  identityPhotoLink: $("#identity-photo-link"), identityPhotoImage: $("#identity-photo-image"), identityPhotoStatus: $("#identity-photo-status"), identityPhotoPlaceholder: $("#identity-photo-placeholder"), identityPhotoMeta: $("#identity-photo-meta"),
  refreshRecharges: $("#refresh-recharges"), rechargeForm: $("#recharge-form"), rechargeSearch: $("#recharge-search"), rechargeResults: $("#recharge-results"), rechargeSelection: $("#recharge-selection"), rechargeDriver: $("#recharge-driver"), rechargeAmount: $("#recharge-amount"), rechargeReference: $("#recharge-reference"), rechargeNote: $("#recharge-note"), rechargePagePreview: $("#recharge-page-preview"), rechargesBody: $("#recharges-body"),
  refreshRides: $("#refresh-rides"), rideSearch: $("#ride-search"), rideFilter: $("#ride-filter"), rideCount: $("#ride-count"), ridesBody: $("#rides-body"),
  refreshReceipts: $("#refresh-receipts"), receiptSearch: $("#receipt-search"), receiptCount: $("#receipt-count"), receiptsBody: $("#receipts-body"),
  refreshCommission: $("#refresh-commission"), commissionForm: $("#commission-form"), financeCategories: $("#finance-categories"), exchangeUsd: $("#exchange-usd"), exchangeEtb: $("#exchange-etb"), commissionPreview: $("#commission-preview"),
  refreshCommissionCollected: $("#refresh-commission-collected"), commissionStats: $("#commission-stats"), commissionByCategory: $("#commission-by-category"),
  receiptDialog: $("#receipt-dialog"), receiptContent: $("#receipt-content"), receiptClose: $("#receipt-close"), receiptDownload: $("#receipt-download"),
  refreshActivity: $("#refresh-activity"), activityBody: $("#activity-body"), toast: $("#toast"), dialog: $("#confirm-dialog"),
  confirmTitle: $("#confirm-title"), confirmMessage: $("#confirm-message"), confirmCancel: $("#confirm-cancel"), confirmAccept: $("#confirm-accept"),
};

let drivers = [];
let rides = [];
let receipts = [];
let recharges = [];
let selectedDriverId = null;
const driverReviews = new Map();
let documentRenderId = 0;
let toastTimer = null;
let confirmResolver = null;
let latestRechargeReceipt = null;
const financeCategoryIds = ["standard", "boda", "rickshaw", "comfort", "premium"];

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
  if (view === "receipts" && receipts.length === 0) loadReceipts();
  if (view === "recharges") loadRecharges();
  if (view === "finance") loadCommission();
  if (view === "commission-collected") loadCommissionCollected();
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
function searchableDriver(driver) { return [driver.firstName, driver.lastName, driver.phoneNumber, driver.plateNumber, driver.vehicleType, ...(driver.vehicleClasses || []), driver.driverId].join(" ").toLowerCase(); }
function driverMatchesFilter(driver, filter) {
  const wallet = driver.wallet || {};
  return filter === "all" || (filter === "pending" && driver.reviewStatus === "pending") || (filter === "low" && wallet.isLowBalance) || (filter === "blocked" && wallet.status === "suspended") || (filter === "unclassified" && driver.requiresVehicleClass && !(driver.vehicleClasses || []).length);
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
    renderDriverList(); renderDriverDetail(selectedDriver()); renderRechargeDrivers();
  } catch (error) { showToast(readableError(error), "error"); }
  finally { setBusy(el.refreshDrivers, false); }
}

async function selectDriver(driverId) {
  selectedDriverId = driverId;
  renderDriverList();
  renderDriverDetail(selectedDriver());
  await Promise.all([loadLedger(driverId), loadDriverReview(driverId)]);
}

function detailRows(container, values) {
  container.replaceChildren();
  for (const [label, value] of values) {
    const row = document.createElement("div");
    const term = document.createElement("dt"); term.textContent = label;
    const description = document.createElement("dd"); description.textContent = value || "Not provided";
    row.append(term, description); container.append(row);
  }
}

function resetDocumentPreview(link, image, status, placeholder, message) {
  if (link.dataset.objectUrl) URL.revokeObjectURL(link.dataset.objectUrl);
  delete link.dataset.objectUrl;
  link.hidden = true; link.removeAttribute("href"); image.removeAttribute("src");
  status.textContent = message; placeholder.textContent = message; placeholder.hidden = false;
}

async function renderDocumentPreview({ path, link, image, status, placeholder, renderId }) {
  if (!path) {
    resetDocumentPreview(link, image, status, placeholder, "Not uploaded");
    return;
  }
  resetDocumentPreview(link, image, status, placeholder, "Loading secure image…");
  try {
    const blob = await getBlob(storageRef(storage, path), 10 * 1024 * 1024);
    if (renderId !== documentRenderId) return;
    const url = URL.createObjectURL(blob); link.dataset.objectUrl = url;
    link.href = url; image.src = url; link.hidden = false; placeholder.hidden = true; status.textContent = "Uploaded — open full size";
  } catch (error) {
    if (renderId !== documentRenderId) return;
    resetDocumentPreview(link, image, status, placeholder, "Image unavailable");
    placeholder.textContent = readableError(error);
  }
}

function updateReviewButtonState() {
  const review = selectedDriverId ? driverReviews.get(selectedDriverId) : null;
  el.saveReview.disabled = el.reviewStatus.value === "approved" && review?.readyForApproval !== true;
}

function renderDriverReview(review) {
  const renderId = ++documentRenderId;
  if (!review) {
    el.reviewReadiness.textContent = "Loading…"; delete el.reviewReadiness.dataset.ready;
    el.reviewChecklist.replaceChildren();
    detailRows(el.identityDetails, [["Status", "Loading review information…"]]);
    detailRows(el.vehicleDetails, [["Status", "Loading review information…"]]);
    detailRows(el.licenceDetails, [["Status", "Loading review information…"]]);
    resetDocumentPreview(el.licenceFrontLink, el.licenceFrontImage, el.licenceFrontStatus, el.licenceFrontPlaceholder, "Loading…");
    resetDocumentPreview(el.licenceBackLink, el.licenceBackImage, el.licenceBackStatus, el.licenceBackPlaceholder, "Loading…");
    resetDocumentPreview(el.identityPhotoLink, el.identityPhotoImage, el.identityPhotoStatus, el.identityPhotoPlaceholder, "Loading…");
    el.identityPhotoMeta.textContent = "";
    updateReviewButtonState();
    return;
  }

  el.reviewReadiness.textContent = review.readyForApproval ? "Ready for approval" : `${review.missingRequirements?.length || 0} item(s) missing`;
  el.reviewReadiness.dataset.ready = String(review.readyForApproval === true);
  el.reviewChecklist.replaceChildren();
  for (const check of review.checks || []) {
    const item = document.createElement("div"); item.className = `review-check${check.passed ? " passed" : ""}`; item.textContent = check.label; el.reviewChecklist.append(item);
  }
  const identity = review.identity || {}; const registration = review.registration || {};
  detailRows(el.identityDetails, [
    ["Full name", `${identity.firstName || ""} ${identity.lastName || ""}`.trim()],
    ["Phone", identity.phoneNumber],
    ["Firebase OTP", identity.phoneVerified ? "Verified" : "Not verified"],
    ["Submitted", dateTime(review.onboardingCompletedAtMillis)],
  ]);
  detailRows(el.vehicleDetails, [
    ["Service", registration.serviceType], ["Vehicle type", registration.vehicleType],
    ["Make and model", `${registration.make || ""} ${registration.model || ""}`.trim()],
    ["Colour", registration.color], ["Year", registration.manufactureYear], ["Plate", registration.plateNumber],
  ]);
  detailRows(el.licenceDetails, [
    ["Country", registration.licenceCountry],
    ["Name", `${registration.licenceFirstName || ""} ${registration.licenceLastName || ""}`.trim()],
    ["Licence number", registration.licenceNumber], ["Issue date", registration.licenceIssueDate],
    ["Upload check", review.documents?.driverLicence?.qualityChecked ? "Passed" : "Not passed"],
  ]);
  const licence = review.documents?.driverLicence || {};
  const identityPhoto = review.documents?.identityPhoto || {};
  void renderDocumentPreview({ path: licence.frontStoragePath, link: el.licenceFrontLink, image: el.licenceFrontImage, status: el.licenceFrontStatus, placeholder: el.licenceFrontPlaceholder, renderId });
  void renderDocumentPreview({ path: licence.backStoragePath, link: el.licenceBackLink, image: el.licenceBackImage, status: el.licenceBackStatus, placeholder: el.licenceBackPlaceholder, renderId });
  void renderDocumentPreview({ path: identityPhoto.storagePath, link: el.identityPhotoLink, image: el.identityPhotoImage, status: el.identityPhotoStatus, placeholder: el.identityPhotoPlaceholder, renderId });
  el.identityPhotoMeta.textContent = identityPhoto.storagePath
    ? `${identityPhoto.status === "approved" ? "Approved" : "Awaiting final admin review"} · submitted ${dateTime(identityPhoto.submittedAtMillis)}${identityPhoto.reviewerMessage ? ` · ${identityPhoto.reviewerMessage}` : ""}`
    : "The driver must submit a live identity photo before approval.";
  el.reviewNote.value = review.reviewNote || "";
  updateReviewButtonState();
}

async function loadDriverReview(driverId) {
  if (driverReviews.has(driverId)) { renderDriverReview(driverReviews.get(driverId)); return; }
  renderDriverReview(null);
  try {
    const result = await api.driverReview({ driverId });
    if (selectedDriverId !== driverId) return;
    driverReviews.set(driverId, result.data || {});
    renderDriverReview(driverReviews.get(driverId));
  } catch (error) {
    if (selectedDriverId !== driverId) return;
    el.reviewReadiness.textContent = "Review unavailable"; el.reviewReadiness.dataset.ready = "false";
    el.reviewChecklist.replaceChildren();
    const item = document.createElement("div"); item.className = "review-check"; item.textContent = readableError(error); el.reviewChecklist.append(item);
    updateReviewButtonState();
  }
}

function renderDriverDetail(driver) {
  if (!driver) { el.empty.hidden = false; el.detail.hidden = true; return; }
  const wallet = driver.wallet || {}; el.empty.hidden = true; el.detail.hidden = false;
  el.name.textContent = `${driver.firstName || ""} ${driver.lastName || ""}`.trim() || "Unnamed driver";
  el.meta.textContent = `${driver.phoneNumber || "No phone"} · ${driver.driverId}`; el.reviewBadge.textContent = driver.reviewStatus || "pending"; el.reviewBadge.dataset.status = driver.reviewStatus || "pending";
  el.walletBalance.textContent = `${money(wallet.balance)} ${wallet.currencyCode || "SSP"}`;
  el.walletStatus.textContent = wallet.status === "suspended" ? "Suspended — cannot work" : wallet.balance <= 0 ? "Recharge required" : wallet.isLowBalance ? "Low balance" : "Ready for rides";
  el.walletCredits.textContent = `${money(wallet.lifetimeCredits)} SSP`; el.walletDebits.textContent = `${money(wallet.lifetimeDebits)} SSP`;
  const classes = driver.vehicleClasses?.length ? driver.vehicleClasses : (driver.vehicleClass ? [driver.vehicleClass] : []);
  el.vehicleType.textContent = driver.vehicleType || "Not recorded"; el.plateNumber.textContent = `${driver.plateNumber || "No plate"} · ${classes.length ? classes.map(vehicleClassLabel).join(", ") : "Class unassigned"}`;
  $$("#vehicle-classes input").forEach((input) => { input.checked = classes.includes(input.value); input.disabled = !driver.requiresVehicleClass; });
  el.saveVehicleClass.disabled = !driver.requiresVehicleClass;
  el.vehicleClassHint.textContent = driver.requiresVehicleClass ? (classes.length ? "A car may qualify for more than one service class after inspection." : "Choose at least one class before approving this vehicle.") : `Automatically classified as ${classes.map(vehicleClassLabel).join(", ") || "its fixed local category"}.`;
  el.reviewStatus.value = driver.reviewStatus || "pending"; el.walletStatusSelect.value = wallet.status || "active";
  renderDriverReview(driverReviews.get(driver.driverId));
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

function renderRechargeDrivers() {
  const query = el.rechargeSearch.value.trim().toLowerCase();
  el.rechargeResults.replaceChildren();
  if (!query) return updateRechargePagePreview();
  drivers.filter((driver) => searchableDriver(driver).includes(query)).slice(0, 8).forEach((driver) => {
    const button = document.createElement("button"); button.type = "button"; button.className = "recharge-result";
    const name = `${driver.firstName || ""} ${driver.lastName || ""}`.trim() || "Unnamed driver";
    button.innerHTML = `<strong></strong><span></span>`;
    button.querySelector("strong").textContent = name;
    button.querySelector("span").textContent = `${driver.phoneNumber || "No phone"} · ${driver.plateNumber || "No plate"}`;
    button.addEventListener("click", () => {
      el.rechargeDriver.value = driver.driverId;
      el.rechargeSearch.value = name;
      el.rechargeResults.replaceChildren();
      el.rechargeSelection.hidden = false;
      el.rechargeSelection.textContent = `${name} · ${driver.phoneNumber || "No phone"} · ${driver.plateNumber || "No plate"}`;
      el.rechargeReference.value = `ALP-${(driver.plateNumber || "DRIVER").replace(/[^a-z0-9]/gi, "").toUpperCase()}-AUTO`;
      updateRechargePagePreview();
    });
    el.rechargeResults.append(button);
  });
  updateRechargePagePreview();
}

function updateRechargePagePreview() {
  const driver = drivers.find((item) => item.driverId === el.rechargeDriver.value);
  const amount = Number(el.rechargeAmount.value);
  el.rechargePagePreview.textContent = driver && Number.isFinite(amount) && amount > 0
    ? `${driver.plateNumber || "No plate"} · recharge ${money(amount)} SSP · new wallet ${money((driver.wallet?.balance || 0) + amount)} SSP`
    : "Choose a driver and amount to preview the recharge.";
}

function pdfEscape(value) { return String(value ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/[()\\]/g, "\\$&"); }
function safeDocumentToken(value, fallback) { const token = String(value || fallback).replace(/[^a-z0-9_-]/gi, "-").replace(/-+/g, "-").replace(/^-|-$/g, ""); return token || fallback; }
function downloadPdfDocument(lines, filename) {
  const safeLines = lines.map((line) => String(line ?? ""));
  const commands = ["BT", "/F1 15 Tf", "50 790 Td", `(${pdfEscape(safeLines[0])}) Tj`, "/F1 11 Tf"];
  safeLines.slice(1).forEach((line) => commands.push("0 -28 Td", `(${pdfEscape(line)}) Tj`)); commands.push("ET");
  const stream = commands.join("\n");
  const objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>", `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"];
  let pdf = "%PDF-1.4\n"; const offsets = [0]; objects.forEach((object, index) => { offsets.push(pdf.length); pdf += `${index + 1} 0 obj\n${object}\nendobj\n`; }); const xref = pdf.length; pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`; offsets.slice(1).forEach((offset) => { pdf += `${String(offset).padStart(10, "0")} 00000 n \n`; }); pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  const link = document.createElement("a"); link.href = URL.createObjectURL(new Blob([pdf], { type: "application/pdf" })); link.download = filename; document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(link.href), 1000);
}
function downloadRechargePdf(receipt) {
  if (!receipt) return;
  const receiptNumber = receipt.receiptNumber || receipt.reference || `ALP-${safeDocumentToken(receipt.plateNumber, "DRIVER")}-${safeDocumentToken(receipt.rechargeId || receipt.transactionId, "RECHARGE")}`;
  const lines = ["ALPHA RIDE - WALLET RECHARGE RECEIPT", `Receipt: ${receiptNumber}`, `Date: ${dateTime(receipt.createdAtMillis)}`, `Driver: ${receipt.driverName || receipt.driverId || "-"}`, `Phone: ${receipt.phoneNumber || "-"}`, `Plate: ${receipt.plateNumber || "-"}`, `Amount: ${money(receipt.amount)} SSP`, `Balance before: ${money(receipt.balanceBefore)} SSP`, `Balance after: ${money(receipt.balanceAfter)} SSP`, `Administrator: ${receipt.administratorEmail || "Authorized admin"}`, `Note: ${receipt.note || "-"}`];
  downloadPdfDocument(lines, `AlphaRide-Recharge-${safeDocumentToken(receiptNumber, "Receipt")}.pdf`);
}
function downloadRideReceiptPdf(receipt) {
  if (!receipt) return;
  const receiptNumber = receipt.receiptNumber || `RIDE-${safeDocumentToken(receipt.rideId || receipt.receiptId, "RECEIPT")}`;
  const lines = ["ALPHA RIDE - TRIP RECEIPT", `Receipt: ${receiptNumber}`, `Completed: ${dateTime(receipt.completedAtMillis)}`, `Ride: ${receipt.rideId || "-"}`, `Service: ${vehicleClassLabel(receipt.rideOptionId)}`, `Route: ${receipt.pickupAddress || "Pickup"} to ${receipt.destinationAddress || "Destination"}`, `Fare: ${money(receipt.finalFare)} ${receipt.currencyCode || "SSP"}`, `Waiting: ${money(receipt.waitingCharge)} SSP`, `Alpha fee: ${money(receipt.platformFee)} SSP`, `Driver net: ${money(receipt.driverNetFare)} SSP`, `Payment: ${receipt.paymentMethod || "cash"}`];
  downloadPdfDocument(lines, `AlphaRide-Trip-${safeDocumentToken(receiptNumber, receipt.rideId || "Receipt")}.pdf`);
}

function showRechargeReceipt(receipt) {
  const receiptNumber = receipt.receiptNumber || receipt.reference || `ALP-${safeDocumentToken(receipt.plateNumber, "DRIVER")}-${safeDocumentToken(receipt.rechargeId || receipt.transactionId, "RECHARGE")}`;
  latestRechargeReceipt = { ...receipt, receiptNumber }; el.receiptContent.replaceChildren();
  [["Receipt", receiptNumber], ["Driver", receipt.driverName], ["Phone", receipt.phoneNumber], ["Plate", receipt.plateNumber], ["Amount", `${money(receipt.amount)} SSP`], ["New balance", `${money(receipt.balanceAfter)} SSP`]].forEach(([label, value]) => { const row = document.createElement("p"); row.innerHTML = `<strong></strong><span></span>`; row.querySelector("strong").textContent = label; row.querySelector("span").textContent = value || "—"; el.receiptContent.append(row); });
  el.receiptDialog.hidden = false;
}

async function loadRecharges() {
  setBusy(el.refreshRecharges, true, "Refreshing…"); el.rechargesBody.replaceChildren();
  try {
    const result = await api.recharges({ limit: 150 }); recharges = Array.isArray(result.data?.recharges) ? result.data.recharges : [];
    recharges.forEach((item) => { const row = cellRow([dateTime(item.createdAtMillis), `${item.driverName || item.driverId?.slice(0, 12) || "—"}\n${item.phoneNumber || ""}`, `+${money(item.amount)} SSP`, item.plateNumber || "—", item.reference || "—", ""] , { 2: "credit" }); const button = document.createElement("button"); button.type = "button"; button.className = "text-button"; button.textContent = "Download PDF"; button.addEventListener("click", () => downloadRechargePdf(item)); row.lastElementChild.append(button); el.rechargesBody.append(row); });
    if (!recharges.length) { const row = cellRow(["No recharges recorded yet."]); row.firstElementChild.colSpan = 6; el.rechargesBody.append(row); }
  } catch (error) { const row = cellRow([readableError(error)]); row.firstElementChild.colSpan = 6; el.rechargesBody.append(row); }
  finally { setBusy(el.refreshRecharges, false); }
}

function renderReceipts() {
  const query = el.receiptSearch.value.trim().toLowerCase();
  const filtered = receipts.filter((receipt) => !query || [receipt.receiptNumber, receipt.rideId, receipt.driverId, receipt.passengerId, receipt.pickupAddress, receipt.destinationAddress].join(" ").toLowerCase().includes(query));
  el.receiptCount.textContent = `${filtered.length} of ${receipts.length} receipts`; el.receiptsBody.replaceChildren();
  filtered.forEach((item) => { const row = cellRow([dateTime(item.completedAtMillis), item.receiptNumber || "Pending", vehicleClassLabel(item.rideOptionId), `${item.pickupAddress || "Pickup"} → ${item.destinationAddress || "Destination"}`, `${money(item.finalFare)} ${item.currencyCode || "SSP"}`, `${money(item.platformFee)} SSP`, `${money(item.driverNetFare)} SSP`, ""], { 1: "receipt-number", 5: "credit" }); const button = document.createElement("button"); button.type = "button"; button.className = "text-button"; button.textContent = "Download PDF"; button.addEventListener("click", () => downloadRideReceiptPdf(item)); row.lastElementChild.append(button); el.receiptsBody.append(row); });
  if (!filtered.length) { const row = cellRow(["No receipts match this search."]); row.firstElementChild.colSpan = 8; el.receiptsBody.append(row); }
}

async function loadReceipts() {
  setBusy(el.refreshReceipts, true, "Refreshing…");
  try { const result = await api.receipts({ limit: 200 }); receipts = Array.isArray(result.data?.receipts) ? result.data.receipts : []; renderReceipts(); }
  catch (error) { showToast(readableError(error), "error"); }
  finally { setBusy(el.refreshReceipts, false); }
}

function updateCommissionPreview() {
  el.commissionPreview.textContent = "Saved settings apply to new quotes and rides. Existing rides keep the fare and commission captured when they were requested.";
}

function financeCategoryCard(id, values = {}) {
  const card = document.createElement("section"); card.className = "finance-category"; card.dataset.category = id;
  card.innerHTML = `<div class="card-title"><div><h2></h2><p class="muted">Independent fare and Alpha commission</p></div><span class="secure-chip">New rides</span></div><div class="finance-inputs"><label>Flag-down / base (SSP)<input data-field="baseFare" type="number" min="0" step="1" required /></label><label>Minimum fare (SSP)<input data-field="minimumFare" type="number" min="0" step="1" required /></label><label>Per kilometre (SSP)<input data-field="perKilometer" type="number" min="1" step="1" required /></label><label>Customer waiting / minute (SSP)<input data-field="waitingPerMinute" type="number" min="1" step="1" required /></label><label>Commission (%)<input data-field="commissionPercent" type="number" min="0" max="50" step="0.01" required /></label></div>`;
  card.querySelector("h2").textContent = vehicleClassLabel(id);
  card.querySelectorAll("input").forEach((input) => { input.value = values[input.dataset.field] ?? 0; });
  return card;
}

async function loadCommission() {
  setBusy(el.refreshCommission, true, "Refreshing…");
  try { const result = await api.businessSettings(); const settings = result.data || {}; el.financeCategories.replaceChildren(...financeCategoryIds.map((id) => financeCategoryCard(id, settings.categories?.[id]))); el.exchangeUsd.value = settings.exchangeRates?.usdToSsp ?? 0; el.exchangeEtb.value = settings.exchangeRates?.etbToSsp ?? 0; updateCommissionPreview(); }
  catch (error) { showToast(readableError(error), "error"); }
  finally { setBusy(el.refreshCommission, false); }
}

async function loadCommissionCollected() {
  setBusy(el.refreshCommissionCollected, true, "Refreshing…");
  try { const { data } = await api.commissionReport(); el.commissionStats.replaceChildren(metricCard("Today", `${money(data.today)} SSP`, "Juba business day", "green"), metricCard("Recorded total", `${money(data.allTime)} SSP`, `${money(data.completedRideCount)} completed rides`, "blue")); el.commissionByCategory.replaceChildren(); financeCategoryIds.forEach((id) => { const row = document.createElement("div"); row.className = "breakdown-row"; const label = document.createElement("span"); label.textContent = vehicleClassLabel(id); const value = document.createElement("strong"); value.textContent = `${money(data.byCategory?.[id])} SSP`; row.append(label, value); el.commissionByCategory.append(row); }); }
  catch (error) { showToast(readableError(error), "error"); }
  finally { setBusy(el.refreshCommissionCollected, false); }
}

function rideStatusLabel(status) { return ({ driver_arriving: "Driver arriving", in_progress: "In progress" })[status] || (status ? status[0].toUpperCase() + status.slice(1) : "Unknown"); }
function renderRides() {
  const query = el.rideSearch.value.trim().toLowerCase(); const filter = el.rideFilter.value;
  const filtered = rides.filter((ride) => {
    const statusMatch = filter === "all" || (filter === "active" && activeStatuses.has(ride.status)) || ride.status === filter;
    return statusMatch && (!query || [ride.rideId, ride.driverId, ride.passengerId, ride.status, ride.rideOptionId, ride.driverName, ride.driverPhone, ride.passengerName, ride.passengerPhone, ride.pickupAddress, ride.destinationAddress].join(" ").toLowerCase().includes(query));
  });
  el.rideCount.textContent = `${filtered.length} of ${rides.length} recent rides`; el.ridesBody.replaceChildren();
  filtered.forEach((ride) => { const row = cellRow([dateTime(ride.updatedAtMillis), ride.rideId.slice(0, 10), rideStatusLabel(ride.status), vehicleClassLabel(ride.rideOptionId), ride.driverName || (ride.driverId ? ride.driverId.slice(0, 10) : "Unassigned"), `${money(ride.finalFare || ride.estimatedFare)} SSP`, ""], { 2: `status-cell status-${ride.status}` }); const button = document.createElement("button"); button.type = "button"; button.className = "text-button"; button.textContent = "View"; const detail = document.createElement("tr"); detail.className = "ride-detail-row"; detail.hidden = true; const cell = document.createElement("td"); cell.colSpan = 7; cell.innerHTML = `<div class="ride-detail-grid"><article><strong>Route</strong><span></span></article><article><strong>Passenger</strong><span></span></article><article><strong>Driver</strong><span></span></article><article><strong>Ride finance</strong><span></span></article></div>`; const spans = cell.querySelectorAll("span"); spans[0].textContent = `${ride.pickupAddress || "Pickup unavailable"} → ${ride.destinationAddress || "Destination unavailable"}`; spans[1].textContent = `${ride.passengerName || "Unknown passenger"} · ${ride.passengerPhone || ride.passengerId || "No phone"}`; spans[2].textContent = `${ride.driverName || "Unassigned"} · ${ride.driverPhone || "No phone"} · ${ride.driverPlateNumber || "No plate"}`; spans[3].textContent = `Fare ${money(ride.finalFare || ride.estimatedFare)} SSP · Alpha fee ${money(ride.platformFee)} SSP · ${ride.paymentMethod || "cash"}`; detail.append(cell); button.addEventListener("click", () => { detail.hidden = !detail.hidden; button.textContent = detail.hidden ? "View" : "Hide"; }); row.lastElementChild.append(button); el.ridesBody.append(row, detail); });
  if (!filtered.length) { const row = cellRow(["No rides match these filters."]); row.firstElementChild.colSpan = 7; el.ridesBody.append(row); }
}

async function loadRides() {
  setBusy(el.refreshRides, true, "Refreshing…");
  try { const result = await api.rides({ limit: 150 }); rides = Array.isArray(result.data?.rides) ? result.data.rides : []; renderRides(); }
  catch (error) { showToast(readableError(error), "error"); }
  finally { setBusy(el.refreshRides, false); }
}

function activityLabel(action) { return ({ driver_review_status: "Driver review", driver_vehicle_class: "Vehicle classes", wallet_top_up: "Wallet recharge", wallet_status: "Wallet access", commission_rate: "Commission rate", business_settings: "Finance controls" })[action] || action.replaceAll("_", " "); }
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
el.refreshRecharges.addEventListener("click", loadRecharges); el.refreshReceipts.addEventListener("click", loadReceipts); el.receiptSearch.addEventListener("input", renderReceipts); el.refreshCommission.addEventListener("click", loadCommission); el.refreshCommissionCollected.addEventListener("click", loadCommissionCollected);
el.reviewStatus.addEventListener("change", updateReviewButtonState);
$$('[data-recharge-amount]').forEach((button) => button.addEventListener("click", () => { el.rechargeAmount.value = button.dataset.rechargeAmount; updateRechargePagePreview(); })); el.rechargeAmount.addEventListener("input", updateRechargePagePreview); el.rechargeSearch.addEventListener("input", () => { el.rechargeDriver.value = ""; el.rechargeSelection.hidden = true; el.rechargeReference.value = ""; renderRechargeDrivers(); });
el.receiptClose.addEventListener("click", () => { el.receiptDialog.hidden = true; }); el.receiptDownload.addEventListener("click", () => downloadRechargePdf(latestRechargeReceipt));

el.rechargeForm.addEventListener("submit", async (event) => {
  event.preventDefault(); const driver = drivers.find((item) => item.driverId === el.rechargeDriver.value); if (!driver) return showToast("Search for and select a driver first.", "error"); const amount = Number(el.rechargeAmount.value);
  const name = `${driver.firstName || ""} ${driver.lastName || ""}`.trim() || "this driver"; const approved = await confirmAction({ title: "Confirm wallet recharge", message: `Add ${money(amount)} SSP to ${name} (${driver.plateNumber || "no plate"})? The receipt number is generated automatically.`, confirmLabel: `Add ${money(amount)} SSP` }); if (!approved) return;
  const button = el.rechargeForm.querySelector("button[type=submit]"); setBusy(button, true, "Recording…");
  try { const result = await api.creditWallet({ driverId: driver.driverId, amount, note: el.rechargeNote.value.trim() }); const receipt = result.data?.receipt; el.rechargeForm.reset(); el.rechargeSelection.hidden = true; el.rechargeResults.replaceChildren(); if (receipt) showRechargeReceipt(receipt); showToast("Wallet recharge recorded successfully."); await Promise.all([loadDrivers(), loadRecharges(), loadOverview()]); }
  catch (error) { showToast(readableError(error), "error"); } finally { setBusy(button, false); updateRechargePagePreview(); }
});

el.saveVehicleClass.addEventListener("click", async () => { const driver = selectedDriver(); if (!driver?.requiresVehicleClass) return; const vehicleClasses = $$("#vehicle-classes input:checked").map((input) => input.value); if (!vehicleClasses.length) return showToast("Select at least one Alpha ride class.", "error"); const labels = vehicleClasses.map(vehicleClassLabel).join(", "); const approved = await confirmAction({ title: "Change ride classes?", message: `Assign ${el.name.textContent} to ${labels} after physical inspection?`, confirmLabel: "Save classes" }); if (!approved) return; setBusy(el.saveVehicleClass, true); try { await api.vehicleClass({ driverId: driver.driverId, vehicleClasses }); showToast("Driver ride classes updated."); await Promise.all([loadDrivers(), loadOverview()]); } catch (error) { showToast(readableError(error), "error"); } finally { setBusy(el.saveVehicleClass, false); } });

el.commissionForm.addEventListener("submit", async (event) => { event.preventDefault(); const categories = {}; $$(".finance-category").forEach((card) => { const values = {}; card.querySelectorAll("input").forEach((input) => { values[input.dataset.field] = Number(input.value); }); categories[card.dataset.category] = values; }); const approved = await confirmAction({ title: "Update finance controls?", message: "New quotes and rides will use these category fares and commission percentages. Existing rides will not change.", confirmLabel: "Save controls" }); if (!approved) return; const button = el.commissionForm.querySelector("button[type=submit]"); setBusy(button, true, "Saving…"); try { await api.setBusinessSettings({ categories, exchangeRates: { usdToSsp: Number(el.exchangeUsd.value || 0), etbToSsp: Number(el.exchangeEtb.value || 0) } }); showToast("Finance controls updated for new rides."); await Promise.all([loadCommission(), loadActivity(), loadOverview()]); } catch (error) { showToast(readableError(error), "error"); } finally { setBusy(button, false); } });
el.saveReview.addEventListener("click", async () => { const driver = selectedDriver(); if (!driver) return; const status = el.reviewStatus.value; const review = driverReviews.get(driver.driverId); if (status === "approved" && review?.readyForApproval !== true) return showToast("Complete every identity and document check before approval.", "error"); const note = el.reviewNote.value.trim(); const approved = await confirmAction({ title: `${rideStatusLabel(status)} this driver?`, message: status === "approved" ? `Approve ${el.name.textContent} after checking the identity photo, personal details, vehicle and both licence images?` : `Change ${el.name.textContent}'s review status to ${status}${note ? ` with note: ${note}` : "."}`, confirmLabel: "Save status" }); if (!approved) return; setBusy(el.saveReview, true); try { await api.reviewStatus({ driverId: driver.driverId, reviewStatus: status, note }); driverReviews.delete(driver.driverId); showToast("Driver review status updated."); await Promise.all([loadDrivers(), loadOverview(), loadDriverReview(driver.driverId)]); } catch (error) { showToast(readableError(error), "error"); } finally { setBusy(el.saveReview, false); updateReviewButtonState(); } });
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
