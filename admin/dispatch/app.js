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
  searchPlaces: call("customerServiceSearchPlaces"),
  getPlace: call("customerServiceGetPlace"),
  quoteRide: call("customerServiceQuoteRide"),
  createRide: call("customerServiceCreateRide"),
  listBookings: call("customerServiceListBookings"),
  cancelRide: call("customerServiceCancelRide"),
};

const $ = (selector) => document.querySelector(selector);
const el = {
  loginView: $("#login-view"), dispatchView: $("#dispatch-view"), loginForm: $("#login-form"), loginError: $("#login-error"),
  email: $("#email"), password: $("#password"), agentEmail: $("#agent-email"), logout: $("#logout"),
  bookingForm: $("#booking-form"), customerName: $("#customer-name"), customerPhone: $("#customer-phone"), customerNote: $("#customer-note"),
  pickupSearch: $("#pickup-search"), pickupResults: $("#pickup-results"), pickupSelected: $("#pickup-selected"),
  destinationSearch: $("#destination-search"), destinationResults: $("#destination-results"), destinationSelected: $("#destination-selected"),
  dispatchMap: $("#dispatch-map"), mapStatus: $("#map-status"),
  quoteCard: $("#quote-card"), quoteFare: $("#quote-fare"), quoteDistance: $("#quote-distance"), quoteDuration: $("#quote-duration"),
  bookingError: $("#booking-error"), createBooking: $("#create-booking"), refreshBookings: $("#refresh-bookings"), bookingsList: $("#bookings-list"), toast: $("#toast"),
};

const activeStatuses = new Set(["requested", "offered", "accepted", "driver_arriving", "arrived"]);
let pickup = null;
let destination = null;
let quote = null;
let quoteSequence = 0;
let toastTimer = null;
let map = null;
let pickupMarker = null;
let destinationMarker = null;
let routeLine = null;
const searchTimers = new Map();

const rideOption = () => document.querySelector('input[name="ride-option"]:checked')?.value || "standard";
const money = (value) => new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(Number(value) || 0);
const dateTime = (millis) => millis ? new Date(millis).toLocaleString([], { dateStyle: "medium", timeStyle: "short" }) : "Just now";
const readableError = (error) => (typeof error?.message === "string" ? error.message : "")
  .replace(/^Firebase:\s*/i, "").replace(/^Functions:\s*/i, "").replace(/\s*\([^)]*\)\.?$/, "").trim() || "The operation could not be completed.";

function showToast(message, tone = "success") {
  clearTimeout(toastTimer);
  el.toast.textContent = message;
  el.toast.dataset.tone = tone;
  el.toast.hidden = false;
  toastTimer = setTimeout(() => { el.toast.hidden = true; }, 4500);
}

function setError(element, message = "") {
  element.textContent = message;
  element.hidden = !message;
}

function setBusy(button, busy, label = "Working…") {
  button.dataset.label ||= button.textContent;
  button.disabled = busy;
  button.textContent = busy ? label : button.dataset.label;
}

function selectedPayload() {
  return {
    customerName: el.customerName.value.trim(),
    customerPhone: el.customerPhone.value.trim(),
    customerNote: el.customerNote.value.trim(),
    pickup,
    destination,
    rideOptionId: rideOption(),
  };
}

function mapIcon(kind) {
  return window.L.divIcon({
    className: "",
    html: `<div class="alpha-map-pin ${kind}"></div>`,
    iconSize: [28, 28],
    iconAnchor: [14, 28],
    popupAnchor: [0, -28],
  });
}

function ensureMap() {
  if (map || !window.L || !el.dispatchMap) return;
  map = window.L.map(el.dispatchMap, { zoomControl: true }).setView(
    [4.8594, 31.5713],
    13,
  );
  window.L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(map);
}

function removeMapLayer(layer) {
  if (map && layer) map.removeLayer(layer);
}

function decodePolyline(encoded) {
  if (typeof encoded !== "string" || !encoded) return [];
  const points = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;
  while (index < encoded.length) {
    let result = 0;
    let shift = 0;
    let byte;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    latitude += result & 1 ? ~(result >> 1) : result >> 1;
    result = 0;
    shift = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    longitude += result & 1 ? ~(result >> 1) : result >> 1;
    points.push([latitude / 1e5, longitude / 1e5]);
  }
  return points;
}

function drawRoute(encodedPolyline) {
  ensureMap();
  removeMapLayer(routeLine);
  routeLine = null;
  const points = decodePolyline(encodedPolyline);
  if (!map || points.length < 2) return;
  routeLine = window.L.polyline(points, {
    color: "#08783c",
    weight: 6,
    opacity: 0.88,
    lineCap: "round",
  }).addTo(map);
  map.fitBounds(routeLine.getBounds(), { padding: [36, 36], maxZoom: 16 });
}

function updateMap() {
  ensureMap();
  if (!map) return;
  removeMapLayer(pickupMarker);
  removeMapLayer(destinationMarker);
  removeMapLayer(routeLine);
  pickupMarker = null;
  destinationMarker = null;
  routeLine = null;
  if (pickup) {
    const pickupPopup = document.createElement("span");
    pickupPopup.textContent = `Pickup: ${pickup.address}`;
    pickupMarker = window.L.marker([pickup.latitude, pickup.longitude], {
      icon: mapIcon("pickup"),
      title: "Pickup",
    }).addTo(map).bindPopup(pickupPopup);
  }
  if (destination) {
    const destinationPopup = document.createElement("span");
    destinationPopup.textContent = `Destination: ${destination.address}`;
    destinationMarker = window.L.marker(
      [destination.latitude, destination.longitude],
      { icon: mapIcon("destination"), title: "Destination" },
    ).addTo(map).bindPopup(destinationPopup);
  }
  if (pickup && destination) {
    map.fitBounds(
      [[pickup.latitude, pickup.longitude], [destination.latitude, destination.longitude]],
      { padding: [42, 42], maxZoom: 16 },
    );
    el.mapStatus.textContent = "Locations selected. Calculating the road route…";
  } else if (pickup || destination) {
    const point = pickup || destination;
    map.setView([point.latitude, point.longitude], 16);
    el.mapStatus.textContent = pickup
      ? "Pickup selected. Now choose the destination."
      : "Destination selected. Now choose the pickup.";
  } else {
    map.setView([4.8594, 31.5713], 13);
    el.mapStatus.textContent = "Select pickup and destination from the search results.";
  }
}

function clearQuote(message = "Select both locations") {
  quoteSequence += 1;
  quote = null;
  el.quoteFare.textContent = message;
  el.quoteDistance.textContent = "—";
  el.quoteDuration.textContent = "—";
  el.createBooking.disabled = true;
}

async function refreshQuote() {
  if (!pickup || !destination) {
    clearQuote();
    return;
  }
  const sequence = ++quoteSequence;
  quote = null;
  el.quoteFare.textContent = "Calculating…";
  el.quoteDistance.textContent = "Road route";
  el.quoteDuration.textContent = "Please wait";
  el.createBooking.disabled = true;
  setError(el.bookingError);
  try {
    const { data } = await api.quoteRide(selectedPayload());
    if (sequence !== quoteSequence) return;
    quote = data;
    el.quoteFare.textContent = `${money(data.estimatedFare)} ${data.currencyCode || "SSP"}`;
    el.quoteDistance.textContent = `${(Number(data.routeDistanceMeters) / 1000).toFixed(1)} km`;
    el.quoteDuration.textContent = `${Math.max(1, Math.round(Number(data.routeDurationSeconds) / 60))} min`;
    drawRoute(data.encodedPolyline);
    el.mapStatus.textContent = "Road route and fare are ready.";
    el.createBooking.disabled = false;
  } catch (error) {
    if (sequence !== quoteSequence) return;
    clearQuote("Quote unavailable");
    setError(el.bookingError, readableError(error));
  }
}

function renderSuggestions(container, results, choose) {
  container.replaceChildren();
  if (!results.length) {
    const empty = document.createElement("div");
    empty.className = "suggestion";
    empty.textContent = "No matching location found.";
    container.append(empty);
    container.hidden = false;
    return;
  }
  results.forEach((result) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "suggestion";
    button.setAttribute("role", "option");
    const primary = document.createElement("b");
    primary.textContent = result.primaryText || result.description;
    const secondary = document.createElement("small");
    secondary.textContent = result.secondaryText || result.description || "South Sudan";
    button.append(primary, secondary);
    button.addEventListener("click", () => choose(result));
    container.append(button);
  });
  container.hidden = false;
}

function renderSearchStatus(container, message, tone = "neutral") {
  container.replaceChildren();
  const status = document.createElement("div");
  status.className = "suggestion search-status";
  status.dataset.tone = tone;
  status.textContent = message;
  container.append(status);
  container.hidden = false;
}

function setupPlaceSearch({ input, results, selected, assign }) {
  input.addEventListener("input", () => {
    assign(null);
    updateMap();
    selected.hidden = true;
    clearQuote();
    clearTimeout(searchTimers.get(input));
    const query = input.value.trim();
    if (query.length < 2) {
      results.hidden = true;
      return;
    }
    searchTimers.set(input, setTimeout(async () => {
      renderSearchStatus(results, "Searching locations…");
      try {
        const response = await api.searchPlaces({ query });
        if (input.value.trim() !== query) return;
        renderSuggestions(results, response.data.results || [], async (suggestion) => {
          results.hidden = true;
          input.value = suggestion.description || suggestion.primaryText;
          input.disabled = true;
          try {
            const placeResponse = await api.getPlace({ placeId: suggestion.placeId });
            const place = placeResponse.data;
            assign(place);
            updateMap();
            input.value = place.address;
            selected.textContent = "Location selected";
            selected.hidden = false;
            await refreshQuote();
          } catch (error) {
            assign(null);
            selected.hidden = true;
            showToast(readableError(error), "error");
          } finally {
            input.disabled = false;
            input.focus();
          }
        });
      } catch (error) {
        if (input.value.trim() !== query) return;
        const message = readableError(error);
        renderSearchStatus(results, message, "error");
        showToast(message, "error");
      }
    }, 320));
  });
  input.addEventListener("blur", () => setTimeout(() => { results.hidden = true; }, 180));
}

function statusLabel(status) {
  return ({ requested: "Finding driver", offered: "Driver notified", accepted: "Accepted", driver_arriving: "Driver coming", arrived: "Driver arrived", in_progress: "In progress", completed: "Completed", cancelled: "Cancelled", expired: "No driver found" })[status] || status || "Unknown";
}

function bookingCard(booking) {
  const card = document.createElement("article");
  card.className = "booking-card";
  const top = document.createElement("div"); top.className = "booking-top";
  const title = document.createElement("h3"); title.textContent = booking.customerName || "Phone customer";
  const status = document.createElement("span"); status.className = "status"; status.dataset.status = booking.status; status.textContent = statusLabel(booking.status);
  top.append(title, status);
  const phone = document.createElement("a"); phone.className = "phone-link"; phone.href = `tel:${booking.customerPhone}`; phone.textContent = booking.customerPhone || booking.customerPhoneMasked || "No phone";
  const route = document.createElement("div"); route.className = "booking-route";
  const pickupLine = document.createElement("span"); pickupLine.textContent = `Pickup: ${booking.pickup?.address || "—"}`;
  const destinationLine = document.createElement("span"); destinationLine.textContent = `To: ${booking.destination?.address || "—"}`;
  route.append(pickupLine, destinationLine);
  const meta = document.createElement("div"); meta.className = "booking-meta";
  const price = document.createElement("strong"); price.textContent = `${money(booking.finalFare || booking.estimatedFare)} ${booking.currencyCode || "SSP"}`;
  const time = document.createElement("span"); time.textContent = dateTime(booking.requestedAtMillis);
  meta.append(price, time);
  card.append(top, phone, route, meta);
  if (booking.driverName || activeStatuses.has(booking.status)) {
    const actions = document.createElement("div"); actions.className = "booking-actions";
    const driver = document.createElement("span"); driver.className = "muted"; driver.textContent = booking.driverName ? `Driver: ${booking.driverName}` : "Waiting for a driver";
    actions.append(driver);
    if (activeStatuses.has(booking.status)) {
      const cancel = document.createElement("button"); cancel.type = "button"; cancel.className = "cancel-button"; cancel.textContent = "Cancel booking";
      cancel.addEventListener("click", () => cancelBooking(booking, cancel));
      actions.append(cancel);
    }
    card.append(actions);
  }
  return card;
}

async function loadBookings() {
  setBusy(el.refreshBookings, true, "Loading…");
  try {
    const { data } = await api.listBookings({ limit: 60 });
    const bookings = data.bookings || [];
    el.bookingsList.replaceChildren();
    if (!bookings.length) {
      const empty = document.createElement("p"); empty.className = "empty"; empty.textContent = "No phone bookings yet."; el.bookingsList.append(empty);
    } else bookings.forEach((booking) => el.bookingsList.append(bookingCard(booking)));
  } catch (error) {
    el.bookingsList.replaceChildren();
    const failure = document.createElement("p"); failure.className = "empty form-error"; failure.textContent = readableError(error); el.bookingsList.append(failure);
  } finally { setBusy(el.refreshBookings, false); }
}

async function cancelBooking(booking, button) {
  if (!window.confirm(`Cancel the ride for ${booking.customerName || booking.customerPhone}?`)) return;
  setBusy(button, true, "Cancelling…");
  try {
    await api.cancelRide({ rideId: booking.rideId, reason: "Caller cancelled through customer service" });
    showToast("Phone booking cancelled.");
    await loadBookings();
  } catch (error) {
    showToast(readableError(error), "error");
    setBusy(button, false);
  }
}

function resetBookingForm() {
  el.bookingForm.reset();
  document.querySelector('input[name="ride-option"][value="standard"]').checked = true;
  pickup = null;
  destination = null;
  el.pickupSelected.hidden = true;
  el.destinationSelected.hidden = true;
  updateMap();
  clearQuote();
  el.customerName.focus();
}

el.bookingForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!pickup || !destination || !quote) {
    setError(el.bookingError, "Select both locations and wait for the fare estimate.");
    return;
  }
  setBusy(el.createBooking, true, "Sending request…");
  setError(el.bookingError);
  try {
    const { data } = await api.createRide(selectedPayload());
    showToast(data.status === "offered" ? "Nearby drivers were notified." : "Booking saved. No eligible driver is online yet.");
    resetBookingForm();
    await loadBookings();
  } catch (error) {
    setError(el.bookingError, readableError(error));
  } finally {
    if (quote) setBusy(el.createBooking, false);
    else { el.createBooking.textContent = el.createBooking.dataset.label || "Send ride request"; el.createBooking.disabled = true; }
  }
});

document.querySelectorAll('input[name="ride-option"]').forEach((input) => input.addEventListener("change", refreshQuote));
el.refreshBookings.addEventListener("click", loadBookings);
el.logout.addEventListener("click", () => signOut(auth));
el.loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const button = event.submitter;
  setBusy(button, true, "Signing in…");
  setError(el.loginError);
  try { await signInWithEmailAndPassword(auth, el.email.value.trim(), el.password.value); }
  catch (error) { setError(el.loginError, readableError(error)); setBusy(button, false); }
});

setupPlaceSearch({ input: el.pickupSearch, results: el.pickupResults, selected: el.pickupSelected, assign: (value) => { pickup = value; } });
setupPlaceSearch({ input: el.destinationSearch, results: el.destinationResults, selected: el.destinationSelected, assign: (value) => { destination = value; } });

onAuthStateChanged(auth, async (user) => {
  if (!user) {
    el.loginView.hidden = false;
    el.dispatchView.hidden = true;
    return;
  }
  try {
    const token = await getIdTokenResult(user, true);
    if (token.claims.customerService !== true && token.claims.admin !== true) {
      await signOut(auth);
      setError(el.loginError, "This account does not have customer-service access.");
      return;
    }
    el.agentEmail.textContent = user.email || "Authorized operator";
    el.loginView.hidden = true;
    el.dispatchView.hidden = false;
    ensureMap();
    setTimeout(() => map?.invalidateSize(), 80);
    await loadBookings();
  } catch (error) {
    await signOut(auth);
    setError(el.loginError, readableError(error));
  }
});
