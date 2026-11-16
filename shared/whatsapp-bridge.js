/*
 * Notchy — the WhatsApp Web bridge.
 *
 * Injected at document start into web.whatsapp.com, by WKUserScript on the Mac
 * and by Tauri's initialization_script on Windows and Linux. One file for both,
 * so the two platforms cannot drift apart on the part most likely to break.
 *
 * What it does, and nothing more:
 *  - Receives. WhatsApp Web announces a message by creating a desktop
 *    notification. The page gets a Notification that is always "granted" and
 *    hands each one to the app instead of drawing it. The page is also told it
 *    is hidden and unfocused while nobody is looking at it, which is what keeps
 *    it announcing messages and what stops it marking them read.
 *  - Reports whether the page is asking for the QR code or showing the chats.
 *  - Replies. `__notchy.send(...)` opens the conversation, types the text and
 *    sends it, then attaches each file and sends that.
 *
 * WhatsApp changes its markup without notice. Every selector is in SELECTORS,
 * each with alternatives, so a break is a one-line fix here and nowhere else.
 */
(function () {
  "use strict";
  if (window.__notchy) return;

  // ---------------------------------------------------------------------------
  // Where WhatsApp keeps things. data-icon names and ids have outlived every
  // redesign so far; aria-labels are localized, so they are a last resort.
  // ---------------------------------------------------------------------------
  const SELECTORS = {
    qr: ["div[data-ref] canvas", "canvas[aria-label*='QR' i]", "div[data-ref]"],
    chatList: ["#pane-side", "div[aria-label][role='grid']", "#side"],
    searchBox: [
      "#side div[contenteditable='true']",
      "#side input[type='text']",
      "#side input[role='textbox']",
      "div[contenteditable='true'][data-tab='3']",
    ],
    chatTitle: ["#pane-side span[title]", "#pane-side [role='gridcell'] span[dir='auto'][title]"],
    chatRow: ["[role='listitem']", "[role='row']", "div[tabindex='-1']"],
    openChatTitle: ["#main header span[dir='auto'][title]", "#main header span[title]", "#main header span[dir='auto']"],
    composeBox: [
      "#main footer div[contenteditable='true'][role='textbox']",
      "#main footer div[contenteditable='true']",
      "footer div[contenteditable='true']",
    ],
    sendIcon: [
      "[data-icon='send']",
      "[data-icon='wds-ic-send-filled']",
      "[data-icon='send-light']",
    ],
    attachButton: [
      "#main footer [data-icon='plus']",
      "#main footer [data-icon='plus-rounded']",
      "#main footer [data-icon='attach-menu-plus']",
      "#main footer [data-icon='clip']",
    ],
    mediaInput: ["input[type='file'][accept*='image']"],
    documentInput: ["input[type='file'][accept='*']", "input[type='file']:not([accept*='image'])"],
  };

  function find(names, root) {
    const scope = root || document;
    for (const selector of SELECTORS[names] || names) {
      const found = scope.querySelector(selector);
      if (found) return found;
    }
    return null;
  }

  function findAll(names, root) {
    const scope = root || document;
    const out = [];
    for (const selector of SELECTORS[names] || names) {
      for (const node of scope.querySelectorAll(selector)) {
        if (!out.includes(node)) out.push(node);
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // The way out: whichever host injected us.
  //
  // The Mac has a script message handler. Windows deliberately has nothing the
  // page can call: giving web.whatsapp.com a Tauri capability would make it a
  // remote origin with access to the app's commands. So there the events wait
  // in an outbox, and the page rings for them by flipping an invisible
  // character on the end of its title; the app hears the title change and
  // drains the outbox with an eval of its own.
  // ---------------------------------------------------------------------------
  const BELL = "\u200b";
  const outbox = [];

  function ring() {
    const title = document.title || "";
    document.title = title.endsWith(BELL) ? title.slice(0, -1) : title + BELL;
  }

  function post(event) {
    try {
      const mac = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.notchy;
      if (mac) {
        mac.postMessage(event);
        return;
      }
    } catch (_) {
      // Fall through to the outbox.
    }
    outbox.push(event);
    // Bounded: a host that never drains must not grow the page without end.
    if (outbox.length > 200) outbox.splice(0, outbox.length - 200);
    ring();
  }

  /// Everything waiting, handed over once.
  function drain() {
    return outbox.splice(0, outbox.length);
  }

  // ---------------------------------------------------------------------------
  // Seen or not. While the app is not showing the page, WhatsApp is told it is
  // in a background tab: that is when it announces messages, and when it does
  // not send read receipts for whatever chat happens to be open.
  // ---------------------------------------------------------------------------
  let shown = false;

  function defineGetter(target, name, getter) {
    try {
      Object.defineProperty(target, name, { configurable: true, get: getter });
    } catch (_) {}
  }

  defineGetter(Document.prototype, "visibilityState", function () { return shown ? "visible" : "hidden"; });
  defineGetter(Document.prototype, "hidden", function () { return !shown; });
  defineGetter(Document.prototype, "webkitVisibilityState", function () { return shown ? "visible" : "hidden"; });
  defineGetter(Document.prototype, "webkitHidden", function () { return !shown; });
  const realHasFocus = Document.prototype.hasFocus;
  Document.prototype.hasFocus = function () {
    return shown ? realHasFocus.call(this) : false;
  };

  function setShown(value) {
    const next = !!value;
    if (next === shown) return;
    shown = next;
    document.dispatchEvent(new Event("visibilitychange"));
    window.dispatchEvent(new Event(next ? "focus" : "blur"));
  }

  // ---------------------------------------------------------------------------
  // Receiving. Each notification the page creates is kept, by a key of ours,
  // because its onclick is the one reliable way to open that conversation.
  // ---------------------------------------------------------------------------
  const notifications = new Map();
  const MAX_KEPT = 100;
  let counter = 0;

  function newKey() {
    counter += 1;
    return "n" + Date.now().toString(36) + "-" + counter.toString(36);
  }

  function keep(key, handle) {
    notifications.set(key, handle);
    while (notifications.size > MAX_KEPT) {
      notifications.delete(notifications.keys().next().value);
    }
  }

  function announce(title, options, handle) {
    const opts = options || {};
    const key = newKey();
    keep(key, handle);
    post({
      type: "message",
      key: key,
      chat: String(title == null ? "" : title),
      body: String(opts.body == null ? "" : opts.body),
      tag: opts.tag == null ? null : String(opts.tag),
      ts: Date.now(),
    });
    return key;
  }

  class NotchyNotification extends EventTarget {
    constructor(title, options) {
      super();
      const opts = options || {};
      this.title = String(title == null ? "" : title);
      this.body = opts.body || "";
      this.tag = opts.tag || "";
      this.icon = opts.icon || "";
      this.data = opts.data;
      this.silent = !!opts.silent;
      this.onclick = null;
      this.onclose = null;
      this.onshow = null;
      this.onerror = null;
      this.__key = announce(this.title, opts, this);
      const self = this;
      setTimeout(function () {
        const shownEvent = new Event("show");
        self.dispatchEvent(shownEvent);
        if (typeof self.onshow === "function") self.onshow(shownEvent);
      }, 0);
    }
    close() {
      notifications.delete(this.__key);
      const closed = new Event("close");
      this.dispatchEvent(closed);
      if (typeof this.onclose === "function") this.onclose(closed);
    }
    __click() {
      const clicked = new Event("click", { cancelable: true });
      this.dispatchEvent(clicked);
      if (typeof this.onclick === "function") this.onclick(clicked);
    }
    static get permission() { return "granted"; }
    static requestPermission(callback) {
      if (typeof callback === "function") callback("granted");
      return Promise.resolve("granted");
    }
    static get maxActions() { return 0; }
  }

  try {
    Object.defineProperty(window, "Notification", { configurable: true, writable: true, value: NotchyNotification });
  } catch (_) {
    window.Notification = NotchyNotification;
  }

  // A service worker notification cannot be clicked from here, so it is
  // announced without a handle; replying then finds the chat by its name.
  if (window.ServiceWorkerRegistration && ServiceWorkerRegistration.prototype.showNotification) {
    ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
      announce(title, options, null);
      return Promise.resolve();
    };
  }

  // The permission query some builds make before trusting Notification.
  if (navigator.permissions && navigator.permissions.query) {
    const realQuery = navigator.permissions.query.bind(navigator.permissions);
    navigator.permissions.query = function (descriptor) {
      if (descriptor && descriptor.name === "notifications") {
        return Promise.resolve({ state: "granted", status: "granted", onchange: null,
          addEventListener: function () {}, removeEventListener: function () {} });
      }
      return realQuery(descriptor);
    };
  }

  // ---------------------------------------------------------------------------
  // Signed in or not. Watched rather than polled, and reported on change only.
  // ---------------------------------------------------------------------------
  let lastState = null;
  let stateTimer = null;

  function currentState() {
    if (find("chatList")) return "connected";
    if (find("qr")) return "qr";
    return "loading";
  }

  function reportState() {
    stateTimer = null;
    const state = currentState();
    if (state === lastState) return;
    lastState = state;
    post({ type: "state", state: state });
  }

  function scheduleState() {
    if (stateTimer !== null) return;
    stateTimer = setTimeout(reportState, 400);
  }

  function watch() {
    const root = document.documentElement || document;
    new MutationObserver(scheduleState).observe(root, { childList: true, subtree: true });
    scheduleState();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", watch, { once: true });
  } else {
    watch();
  }

  // ---------------------------------------------------------------------------
  // Replying.
  // ---------------------------------------------------------------------------
  function sleep(ms) {
    return new Promise(function (resolve) { setTimeout(resolve, ms); });
  }

  async function waitFor(probe, timeout) {
    const deadline = Date.now() + (timeout || 10000);
    while (Date.now() < deadline) {
      const value = probe();
      if (value) return value;
      await sleep(150);
    }
    return null;
  }

  function clickable(node) {
    if (!node) return null;
    return node.closest("button, [role='button'], span[data-icon], div[tabindex]") || node;
  }

  function press(node) {
    const target = clickable(node);
    if (!target) return false;
    for (const type of ["mousedown", "mouseup", "click"]) {
      target.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
    }
    return true;
  }

  function normalize(text) {
    return String(text || "").replace(/\s+/g, " ").trim().toLowerCase();
  }

  function openChatName() {
    const node = find("openChatTitle");
    if (!node) return "";
    return node.getAttribute("title") || node.textContent || "";
  }

  function isOpen(chat) {
    const open = normalize(openChatName());
    return open !== "" && open === normalize(chat);
  }

  function typeInto(box, text) {
    box.focus();
    if (box.isContentEditable) {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(box);
      selection.removeAllRanges();
      selection.addRange(range);
      document.execCommand("delete", false);
      document.execCommand("insertText", false, text);
    } else {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
      setter.call(box, text);
      box.dispatchEvent(new Event("input", { bubbles: true }));
    }
  }

  async function searchAndOpen(chat) {
    const box = find("searchBox");
    if (!box) return false;
    typeInto(box, chat);
    const wanted = normalize(chat);
    const title = await waitFor(function () {
      for (const node of findAll("chatTitle")) {
        if (normalize(node.getAttribute("title")) === wanted) return node;
      }
      return null;
    }, 8000);
    if (!title) return false;
    let row = null;
    for (const selector of SELECTORS.chatRow) {
      row = title.closest(selector);
      if (row) break;
    }
    press(row || title);
    return true;
  }

  async function openChat(chat, key) {
    if (isOpen(chat)) return true;
    const handle = key ? notifications.get(key) : null;
    if (handle && typeof handle.__click === "function") {
      handle.__click();
      if (await waitFor(function () { return isOpen(chat); }, 5000)) return true;
    }
    // Older notifications for the same chat open it just as well.
    for (const [, other] of Array.from(notifications.entries()).reverse()) {
      if (other && other !== handle && normalize(other.title) === normalize(chat) && typeof other.__click === "function") {
        other.__click();
        if (await waitFor(function () { return isOpen(chat); }, 5000)) return true;
        break;
      }
    }
    if (await searchAndOpen(chat)) {
      if (await waitFor(function () { return isOpen(chat); }, 6000)) return true;
    }
    return false;
  }

  function sendButtonsNow() {
    return new Set(findAll("sendIcon"));
  }

  async function sendText(text) {
    const box = await waitFor(function () { return find("composeBox"); }, 6000);
    if (!box) throw new Error("compose box not found");
    typeInto(box, text);
    // The send button replaces the microphone once there is text.
    const button = await waitFor(function () {
      for (const icon of findAll("sendIcon")) {
        if (icon.closest("footer")) return icon;
      }
      return null;
    }, 4000);
    if (button) {
      press(button);
    } else {
      box.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true }));
    }
    // Wait for the box to empty: that is the message having gone.
    await waitFor(function () {
      const current = find("composeBox");
      return current && normalize(current.textContent) === "";
    }, 6000);
  }

  function toFile(file) {
    const binary = atob(file.base64 || "");
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    return new File([bytes], file.name || "file", { type: file.mime || "application/octet-stream" });
  }

  function transferOf(file) {
    const transfer = new DataTransfer();
    transfer.items.add(file);
    return transfer;
  }

  /// Whatever new send button the media preview brought with it.
  async function waitForPreviewSend(before) {
    return waitFor(function () {
      for (const icon of findAll("sendIcon")) {
        if (!before.has(icon) && !icon.closest("footer")) return icon;
      }
      return null;
    }, 15000);
  }

  async function attachThroughMenu(file, isMedia) {
    const attach = find("attachButton");
    if (!attach) return false;
    press(attach);
    const input = await waitFor(function () {
      return find(isMedia ? "mediaInput" : "documentInput");
    }, 4000);
    if (!input) return false;
    input.files = transferOf(file).files;
    input.dispatchEvent(new Event("change", { bubbles: true }));
    return true;
  }

  async function sendFile(spec) {
    const file = toFile(spec);
    const isImage = /^image\//.test(file.type);
    const before = sendButtonsNow();

    // Images paste the way a screenshot does and arrive as a photo. Anything
    // else is dropped on the conversation, which is how a document goes.
    const box = await waitFor(function () { return find("composeBox"); }, 6000);
    if (!box) throw new Error("compose box not found");
    if (isImage) {
      box.focus();
      box.dispatchEvent(new ClipboardEvent("paste", { clipboardData: transferOf(file), bubbles: true, cancelable: true }));
    } else {
      const main = document.querySelector("#main") || box;
      const transfer = transferOf(file);
      for (const type of ["dragenter", "dragover", "drop"]) {
        main.dispatchEvent(new DragEvent(type, { dataTransfer: transfer, bubbles: true, cancelable: true }));
      }
    }

    let send = await waitForPreviewSend(before);
    if (!send) {
      if (!(await attachThroughMenu(file, isImage))) throw new Error("could not attach " + file.name);
      send = await waitForPreviewSend(before);
    }
    if (!send) throw new Error("no send button for " + file.name);
    press(send);
    // The preview closes once the file is on its way.
    await waitFor(function () { return !document.contains(send); }, 15000);
  }

  function closeChat() {
    const escape = { key: "Escape", code: "Escape", keyCode: 27, which: 27, bubbles: true, cancelable: true };
    document.dispatchEvent(new KeyboardEvent("keydown", escape));
  }

  let queue = Promise.resolve();

  /// One reply at a time: two typed into the same box at once would be one
  /// garbled message.
  function send(request) {
    const run = queue.then(function () { return doSend(request || {}); });
    queue = run.catch(function () {});
    return run;
  }

  async function doSend(request) {
    const requestId = request.requestId || null;
    try {
      if (currentState() !== "connected") throw new Error("WhatsApp is not signed in");
      const chat = String(request.chat || "");
      if (!chat) throw new Error("no conversation");
      if (!(await openChat(chat, request.key))) throw new Error("could not open " + chat);
      const text = String(request.text || "").trim();
      if (text) await sendText(text);
      for (const file of request.files || []) {
        await sendFile(file);
        await sleep(400);
      }
      await sleep(300);
      closeChat();
      post({ type: "sent", requestId: requestId });
      return { ok: true };
    } catch (error) {
      const reason = String((error && error.message) || error);
      post({ type: "sendFailed", requestId: requestId, reason: reason });
      return { ok: false, reason: reason };
    }
  }

  Object.defineProperty(window, "__notchy", {
    configurable: false,
    enumerable: false,
    writable: false,
    value: Object.freeze({
      send: send,
      setShown: setShown,
      state: currentState,
      drain: drain,
    }),
  });
})();
