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
  quoteCard: $("#quote-card"), quoteFare: $("#quote-fare"), quoteDistance: $("#quote-distance"), quoteDuration: $("#quote-duration"),
  bookingError: $("#booking-error"), createBooking: $("#create-booking"), refreshBookings: $("#refresh-bookings"), bookingsList: $("#bookings-list"), toast: $("#toast"),
};

const activeStatuses = new Set(["requested", "offered", "accepted", "driver_arriving", "arrived"]);
let pickup = null;
let destination = null;
let quote = null;
let quoteSequence = 0;
let toastTimer = null;
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

function setupPlaceSearch({ input, results, selected, assign }) {
  input.addEventListener("input", () => {
    assign(null);
    selected.hidden = true;
    clearQuote();
    clearTimeout(searchTimers.get(input));
    const query = input.value.trim();
    if (query.length < 2) {
      results.hidden = true;
      return;
    }
    searchTimers.set(input, setTimeout(async () => {
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
        results.hidden = true;
        showToast(readableError(error), "error");
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
    await loadBookings();
  } catch (error) {
    await signOut(auth);
    setError(el.loginError, readableError(error));
  }
});
