// Where ChatGPT and the site stand, as Rust last said — the "page-state" event.
//
// The pages themselves are native webviews (see island/pageHost.ts). The
// island only draws around and under them, and what it draws there — the dots
// while one loads, the copy when it cannot, the site's spinner, back button and
// tooltip — comes from here. On the Mac the same comes from
// `WebChatController.loadState` and `NotchSiteWeb`'s published fields.

import type { PageLabel, PageState } from "./bridge";
import type { IslandViewName } from "./layout";
import { State } from "./state";
import { t } from "./i18n";

/** Which page a view draws its card for, or null for every card. */
export function pageForView(view: IslandViewName): PageLabel | null {
  if (view === "webchat") return "webchat";
  if (view === "web") return "site";
  return null;
}

const cold = (label: PageLabel): PageState => ({ label, state: "cold", canGoBack: false });

const states: Record<PageLabel, PageState> = { webchat: cold("webchat"), site: cold("site") };
/** How many times each has been told, so an older answer cannot undo a newer event. */
const told: Record<PageLabel, number> = { webchat: 0, site: 0 };

/** Cold until Rust says otherwise: nothing is loaded before a page is opened. */
export function pageState(label: PageLabel): PageState {
  return states[label];
}

/** A "page-state" event, a `pageShow` answer — or a preview pretending to be one. */
export function setPageState(next: PageState) {
  if (next.label !== "webchat" && next.label !== "site") return;
  states[next.label] = { ...next, canGoBack: next.canGoBack === true };
  told[next.label]++;
  State.notify();
}

/**
 * Bumped by every `setPageState`. `pageShow` answers with the state as it was
 * when Rust read it, and an event sent after that read can land first; reading
 * this before the call and again on the answer says whether it is still news.
 */
export function pageStateCount(label: PageLabel): number {
  return told[label];
}

/**
 * The site's name for itself until a page states its own: its host —
 * `NotchSite.hostLabel`, which falls back to "Site" the same way. Here the
 * address is the user's setting rather than a literal, so a broken one still
 * gets a label.
 */
export function siteHost(url: string): string {
  try {
    const host = new URL(url).host;
    if (host) return host;
  } catch {
    // Not a URL: the label below.
  }
  return t("Site");
}

/**
 * WebView2's name for a failed navigation, as the sentence the Mac shows for
 * the same failure — `error.localizedDescription`, which CFNetwork writes in
 * the user's language. Catalogue keys, translated where they are drawn; null
 * for a name with no counterpart there (a failed redirect, an unexpected
 * error), which is then shown as it came.
 *
 * Matched loosely, so `HostNameNotResolved`, `HOST_NAME_NOT_RESOLVED` and
 * `COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED` all land.
 */
export function failureSentence(error: string | undefined): string | null {
  if (!error) return null;
  const name = error.toLowerCase()
    .replace(/^corewebview2_web_error_status_/, "")
    .replace(/[^a-z]/g, "");
  return FAILURES[name] ?? null;
}

/**
 * CFNetwork's wording for the NSURLError a WebKit page gets for the same
 * failure, keyed by WebView2's `CoreWebView2WebErrorStatus` names.
 */
const FAILURES: Record<string, string> = {
  // NSURLErrorServerCertificateUntrusted, -1202
  certificatecommonnameisincorrect: "The certificate for this server is invalid.",
  certificaterevoked: "The certificate for this server is invalid.",
  certificateisinvalid: "The certificate for this server is invalid.",
  // NSURLErrorServerCertificateHasBadDate, -1201
  certificateexpired: "The certificate for this server has expired.",
  // NSURLErrorSecureConnectionFailed, -1200
  clientcertificatecontainserrors: "A TLS error caused the secure connection to fail.",
  // NSURLErrorCannotConnectToHost, -1004
  serverunreachable: "Could not connect to the server.",
  cannotconnect: "Could not connect to the server.",
  // NSURLErrorTimedOut, -1001
  timeout: "The request timed out.",
  // NSURLErrorBadServerResponse, -1011
  errorhttpinvalidserverresponse: "There was a bad response from the server.",
  // NSURLErrorNetworkConnectionLost, -1005
  connectionaborted: "The network connection was lost.",
  connectionreset: "The network connection was lost.",
  // NSURLErrorNotConnectedToInternet, -1009
  disconnected: "The Internet connection appears to be offline.",
  // NSURLErrorCannotFindHost, -1003
  hostnamenotresolved: "A server with the specified hostname could not be found.",
};
