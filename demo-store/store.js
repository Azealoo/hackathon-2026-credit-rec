/*
 * Northbay Electronics: behaviour and data for the fictional demo store.
 *
 * SPEC v2.1 references:
 * - §9.3, §15.7 step 5: laptop, renewed laptop, earbuds and mug checkouts, a saved-card
 *   selector (Mastercard ••5678 default, Visa ••4321, Visa ••1234) and confirm.html.
 * - §5.2 A, §5.3, §6.3, §12.1: the checkout shows "Pay with Mastercard ••5678 [Change]";
 *   the demo path is Change → "Visa ••1234" → Place order.
 * - §7.3: the renewed laptop is listed "Renewed · no warranty".
 * - §15.4: fake identity and the fixture pages (feed.html; checkout.html?blur=1).
 * - §15.5 and contracts/store-pay.*.schema.json: pay() sends and returns the
 *   POST /v1/store/pay shapes. §15.8: the client-side mock is allowed for the static site.
 *
 * Switching PAY_MODE:
 * - By where the page is served: under the FastAPI app's /store/ path the default is
 *   "backend", because /v1/store/pay is then the same origin (§15.7 step 13). Anywhere
 *   else (the Render static site, a local file server) the default is "mock".
 * - For one page load: add ?pay=backend or ?pay=mock to checkout.html, for example
 *   checkout.html?item=laptop&pay=backend. Any other value is ignored.
 *
 * Each page picks its code from <body data-page="…">. The pages' Content-Security-Policy
 * allows no inline scripts, styles or on* attributes, so everything is wired up here, and
 * text from the URL is only ever written with textContent.
 */
"use strict";

// Payment mode. "mock" = client-side approval (Thursday static site, SPEC §15.8).
// "backend" = POST /v1/store/pay on the same origin (when the backend serves this folder at /store/; SPEC §15.5).
const BACKEND_STORE_PATH = /^\/store\//;
const PAY_MODE = BACKEND_STORE_PATH.test(location.pathname) ? "backend" : "mock";
const PAY_URL = "/v1/store/pay";
// Longer than the backend's 7 s processor deadline (visa_acceptance.TIMEOUT_S), so its answer always arrives first.
const PAY_TIMEOUT_MS = 12000;
const MOCK_DELAY_MS = 700;

// Always the same order number, so fixture screenshots are reproducible.
const ORDER_ID = "NB-100234";

// The four products. Prices are integer cents. category is for fixtures and parsers only; it is never shown.
const ITEMS = {
  "laptop": { name: "Aero 14 Laptop, 14-inch", condition: "New", priceCents: 149900, category: "computers", thumb: "laptop" },
  "laptop-renewed": { name: "Aero 14 Laptop, 14-inch", condition: "Renewed · no warranty", priceCents: 109900, category: "computers", thumb: "laptop" },
  "earbuds": { name: "Wireless Earbuds, Noise-Cancelling", condition: "New", priceCents: 24900, category: "audio", thumb: "earbuds" },
  "mug": { name: "Ceramic Coffee Mug, 12 oz", condition: "New", priceCents: 1800, category: "home", thumb: "mug" },
};
const DEFAULT_ITEM = "laptop";

// The store's saved cards: network and last 4 only. The first one is the default.
// Card products and reward data live only in data/cards.json, never here.
const CARDS = [
  { id: "demo-mastercard-5678", label: "Mastercard ••5678" },
  { id: "demo-visa-4321", label: "Visa ••4321" },
  { id: "demo-visa-1234", label: "Visa ••1234" },
];

const PROCESSORS = ["mock", "visa_acceptance_sandbox"];
const PAY_STATUSES = ["approved", "declined", "error"];
const TXN_PATTERN = /^[A-Za-z0-9-]{1,64}$/;
const LONG_DIGIT_RUN = /\d{12,}/;
const PAY_ERROR_TEXT = "Payment didn't go through. Try again.";

const usd = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" });

/* ---------- Small helpers ---------- */

function byId(id) {
  return document.getElementById(id);
}

function setText(id, text) {
  byId(id).textContent = text;
}

function formatCents(cents) {
  return usd.format(cents / 100);
}

function itemFor(key) {
  return Object.hasOwn(ITEMS, key) ? ITEMS[key] : null;
}

function cardById(id) {
  return CARDS.find((card) => card.id === id) || null;
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Points an inline <svg><use> at one of the page's <symbol>s.
function showThumb(useElement, item) {
  useElement.setAttribute("href", "#thumb-" + item.thumb);
}

// Fills the shared item row on checkout.html and confirm.html.
function renderItemRow(item) {
  showThumb(byId("item-thumb"), item);
  setText("item-name", item.name);
  setText("item-condition", item.condition);
  setText("item-price", formatCents(item.priceCents));
}

/* ---------- Payment (SPEC §15.5) ---------- */

// "?pay=backend" or "?pay=mock" overrides PAY_MODE for this page load.
function currentPayMode() {
  const override = new URLSearchParams(location.search).get("pay");
  return override === "backend" || override === "mock" ? override : PAY_MODE;
}

// Eight characters from A–Z and 0–9, so a mock ID can never hold a long digit run.
function randomCode(length) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  const byte = new Uint8Array(1);
  let code = "";
  while (code.length < length) {
    crypto.getRandomValues(byte);
    // 252 = 7 × 36: dropping 252–255 keeps every character equally likely.
    if (byte[0] < 252) {
      code += alphabet[byte[0] % alphabet.length];
    }
  }
  return code;
}

async function payWithMock(request) {
  await wait(MOCK_DELAY_MS);
  const card = cardById(request.savedCardId);
  return {
    status: "approved",
    processor: "mock",
    transactionId: "MOCK-" + randomCode(8),
    cardLabel: card ? card.label : null,
  };
}

// Keeps only the contract's four fields, and rejects anything that isn't that shape.
function toPayResponse(body) {
  if (!body || typeof body !== "object" ||
      !PAY_STATUSES.includes(body.status) || !PROCESSORS.includes(body.processor)) {
    throw new Error("Unexpected payment response");
  }
  return {
    status: body.status,
    processor: body.processor,
    transactionId: typeof body.transactionId === "string" ? body.transactionId : null,
    cardLabel: typeof body.cardLabel === "string" ? body.cardLabel : null,
  };
}

async function payWithBackend(request) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PAY_TIMEOUT_MS);
  try {
    const response = await fetch(PAY_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(request),
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error("Payment request failed: " + response.status);
    }
    return toPayResponse(await response.json());
  } finally {
    clearTimeout(timer);
  }
}

// request: {orderId, savedCardId, amountUsd}. Resolves to {status, processor, transactionId, cardLabel};
// rejects on a network error, timeout, non-2xx answer or a body that isn't that shape.
function pay(request) {
  return currentPayMode() === "backend" ? payWithBackend(request) : payWithMock(request);
}

function confirmUrl(itemKey, cardId, response) {
  const params = [["item", itemKey], ["card", cardId], ["processor", response.processor]];
  if (response.transactionId) {
    params.push(["txn", response.transactionId]);
  }
  return "confirm.html?" + params.map(([key, value]) => key + "=" + encodeURIComponent(value)).join("&");
}

/* ---------- Shop front (index.html) ---------- */

function initShop() {
  const list = byId("products");
  const template = byId("product-template");
  for (const [key, item] of Object.entries(ITEMS)) {
    const row = template.content.firstElementChild.cloneNode(true);
    showThumb(row.querySelector("use"), item);
    row.querySelector(".product-name").textContent = item.name;
    row.querySelector(".product-condition").textContent = item.condition;
    row.querySelector(".product-price").textContent = formatCents(item.priceCents);
    const buy = row.querySelector(".buy-button");
    buy.setAttribute("href", "checkout.html?item=" + encodeURIComponent(key));
    // Both laptops share a name, so the condition tells the two buttons apart.
    buy.setAttribute("aria-label", "Buy now: " + item.name + ", " + item.condition);
    list.append(row);
  }
}

/* ---------- Checkout (checkout.html) ---------- */

function initCheckout() {
  const params = new URLSearchParams(location.search);
  if (params.get("blur") === "1") {
    document.body.classList.add("is-blurred");
  }

  // No ?item= means the laptop, so a bare checkout.html works.
  const itemKey = params.get("item") || DEFAULT_ITEM;
  const item = itemFor(itemKey);
  if (!item) {
    document.title = "Item not found · Northbay Electronics";
    byId("not-found").hidden = false;
    return;
  }

  renderItemRow(item);
  setText("total", formatCents(item.priceCents));
  byId("checkout").hidden = false;

  const sheet = setUpCardSheet();
  const placeOrder = setUpPlaceOrder(itemKey, item, sheet);

  // Coming back from confirm.html out of the back-forward cache restores the old page
  // state. Start again from the default card with a usable button (ruling R8).
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) {
      sheet.reset();
      placeOrder.reset();
    }
  });
}

// The "Pay with" bottom sheet. Picking a card selects it and closes the sheet at once.
// The choice is not saved anywhere: a reload starts again at Mastercard ••5678.
function setUpCardSheet() {
  const page = byId("page");
  const sheet = byId("card-sheet");
  const backdrop = byId("sheet-backdrop");
  const changeButton = byId("change-card");
  const optionList = byId("card-options");
  const template = byId("card-option-template");
  let selected = CARDS[0];

  const options = CARDS.map((card) => {
    const option = template.content.firstElementChild.cloneNode(true);
    option.dataset.cardId = card.id;
    option.querySelector(".card-option-label").textContent = card.label;
    option.addEventListener("click", () => {
      selected = card;
      render();
      close();
    });
    optionList.append(option);
    return option;
  });

  function render() {
    setText("card-label", selected.label);
    for (const option of options) {
      option.setAttribute("aria-checked", String(option.dataset.cardId === selected.id));
    }
  }

  function isOpen() {
    return !sheet.hidden;
  }

  function open() {
    render();
    backdrop.hidden = false;
    sheet.hidden = false;
    page.inert = true;
    document.body.classList.add("sheet-open");
    options[CARDS.indexOf(selected)].focus({ preventScroll: true });
  }

  function close({ returnFocus = true } = {}) {
    if (!isOpen()) {
      return;
    }
    sheet.hidden = true;
    backdrop.hidden = true;
    page.inert = false;
    document.body.classList.remove("sheet-open");
    if (returnFocus) {
      changeButton.focus({ preventScroll: true });
    }
  }

  // Arrow keys move focus between the cards; Enter or Space picks one.
  optionList.addEventListener("keydown", (event) => {
    let step = 0;
    if (event.key === "ArrowDown" || event.key === "ArrowRight") step = 1;
    if (event.key === "ArrowUp" || event.key === "ArrowLeft") step = -1;
    if (step === 0) {
      return;
    }
    event.preventDefault();
    const current = Math.max(0, options.indexOf(document.activeElement));
    options[(current + step + options.length) % options.length].focus();
  });

  changeButton.addEventListener("click", open);
  backdrop.addEventListener("click", () => close());
  byId("sheet-cancel").addEventListener("click", () => close());
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && isOpen()) {
      event.preventDefault();
      close();
    }
  });

  render();

  return {
    selectedCard: () => selected,
    reset() {
      close({ returnFocus: false });
      selected = CARDS[0];
      render();
    },
  };
}

function setUpPlaceOrder(itemKey, item, sheet) {
  const button = byId("place-order");
  const changeButton = byId("change-card");
  const error = byId("pay-error");

  function setBusy(busy) {
    button.disabled = busy;
    changeButton.disabled = busy;
    button.textContent = busy ? "Placing order…" : "Place order";
  }

  button.addEventListener("click", async () => {
    if (button.disabled) {
      return;
    }
    const card = sheet.selectedCard();
    setBusy(true);
    error.textContent = "";
    try {
      const response = await pay({
        orderId: ORDER_ID,
        savedCardId: card.id,
        amountUsd: item.priceCents / 100,
      });
      if (response.status !== "approved") {
        throw new Error("Payment not approved: " + response.status);
      }
      location.assign(confirmUrl(itemKey, card.id, response));
    } catch {
      setBusy(false);
      error.textContent = PAY_ERROR_TEXT;
    }
  });

  return {
    reset() {
      setBusy(false);
      error.textContent = "";
    },
  };
}

/* ---------- Confirmation (confirm.html) ---------- */

// Cybersource IDs can be long numbers; show only the end so the page never has a
// 12-digit run (on-device redaction and the backend's privacy_rejected rule, ruling R9).
// The word joiner (U+2060) stops a line break between "…" and the digits.
function displayTxn(txn) {
  return LONG_DIGIT_RUN.test(txn) ? "…\u2060" + txn.slice(-6) : txn;
}

function statusLine(processor, txn) {
  // No-break space (U+00A0) keeps "txn" on the same line as its ID.
  const txnPart = txn ? " · txn\u00a0" + txn : "";
  if (processor === "visa_acceptance_sandbox") {
    return "Approved · Visa Acceptance sandbox" + txnPart;
  }
  return "Approved · Mock payment, no money moved" + txnPart;
}

function initConfirm() {
  // Every param is checked against an allow-list; anything else falls back to the default.
  const params = new URLSearchParams(location.search);
  const item = itemFor(params.get("item")) || ITEMS[DEFAULT_ITEM];
  const card = cardById(params.get("card")) || CARDS[0];
  const processor = PROCESSORS.includes(params.get("processor")) ? params.get("processor") : "mock";
  const rawTxn = params.get("txn");
  const txn = rawTxn && TXN_PATTERN.test(rawTxn) ? displayTxn(rawTxn) : "";

  renderItemRow(item);
  setText("paid-with", card.label);
  setText("total", formatCents(item.priceCents));
  setText("pay-status", statusLine(processor, txn));
}

/* ---------- Start ---------- */

const PAGE_SETUP = {
  shop: initShop,
  checkout: initCheckout,
  confirm: initConfirm,
};

const pageName = document.body.dataset.page;
if (Object.hasOwn(PAGE_SETUP, pageName)) {
  PAGE_SETUP[pageName]();
}
