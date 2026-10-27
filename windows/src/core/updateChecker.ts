/**
 * Minimal GitHub release update check (#39).
 *
 * The panel asks at most once per local calendar day, remembers the last attempt in
 * `localStorage`, and never runs when the user turned "自动检查更新" off. The network
 * call is injected (`requestLatest`) so the rules are testable without a WebView or
 * GitHub. In production the UI passes the existing `native_http` transport; the Rust
 * allowlist includes `api.github.com` (#29).
 */

export const UPDATE_RELEASES_URL =
  "https://api.github.com/repos/jryang1997/MenuBarMijia/releases/latest";
export const UPDATE_RELEASES_PAGE = "https://github.com/jryang1997/MenuBarMijia/releases/latest";
export const UPDATE_STORAGE_KEY = "menumijia.windows.update.v1";

export interface GitHubRelease {
  /** Version without the leading `v`, e.g. `1.0.7`. */
  readonly version: string;
  /** Original release tag, e.g. `v1.0.7`. */
  readonly tag: string;
  /** GitHub release page, always an https://github.com/ URL. */
  readonly htmlURL: string;
}

export interface UpdateState {
  readonly lastCheckedAtMs: number | null;
  readonly release: GitHubRelease | null;
}

/** Strips an optional `v`/`V` and validates the dotted numeric version shape. */
export function normalizeVersionTag(raw: string): string | null {
  const trimmed = raw.trim().replace(/^v/i, "");
  if (!/^\d+(?:\.\d+)*(?:[-+][0-9A-Za-z.-]+)?$/.test(trimmed)) return null;
  return trimmed;
}

function versionParts(raw: string): number[] {
  const core = (normalizeVersionTag(raw) ?? "0").split(/[-+]/, 1)[0] ?? "0";
  return core.split(".").map((part) => {
    const value = Number.parseInt(part, 10);
    return Number.isFinite(value) ? value : 0;
  });
}

/** Numeric dotted comparison: `1.0.6 < 1.0.10`; pre-release suffixes are ignored. */
export function compareVersions(a: string, b: string): number {
  const left = versionParts(a);
  const right = versionParts(b);
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    const delta = (left[index] ?? 0) - (right[index] ?? 0);
    if (delta !== 0) return delta > 0 ? 1 : -1;
  }
  return 0;
}

export function isNewerVersion(latest: string, current: string): boolean {
  return compareVersions(latest, current) > 0;
}

/** Local calendar day key (`2026-10-27`), so "today" follows the user's clock. */
export function updateCheckDayKey(nowMs: number): string {
  const date = new Date(nowMs);
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${date.getFullYear()}-${month}-${day}`;
}

export function shouldCheckForUpdate(nowMs: number, lastCheckedAtMs: number | null): boolean {
  if (lastCheckedAtMs === null) return true;
  return updateCheckDayKey(nowMs) !== updateCheckDayKey(lastCheckedAtMs);
}

/** Parses `GET /repos/.../releases/latest`; rejects drafts/odd payloads without a tag. */
export function parseLatestRelease(body: string): GitHubRelease | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch {
    return null;
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  const record = parsed as Record<string, unknown>;
  const tag = typeof record["tag_name"] === "string" ? record["tag_name"] : "";
  const version = normalizeVersionTag(tag);
  if (!version) return null;
  const rawURL = typeof record["html_url"] === "string" ? record["html_url"].trim() : "";
  const htmlURL = /^https:\/\/github\.com\/[^\s]+$/i.test(rawURL) ? rawURL : UPDATE_RELEASES_PAGE;
  return { version, tag, htmlURL };
}

export function parseUpdateState(raw: string | null): UpdateState {
  if (!raw) return { lastCheckedAtMs: null, release: null };
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const lastCheckedAtMs =
      typeof parsed["lastCheckedAtMs"] === "number" && Number.isFinite(parsed["lastCheckedAtMs"])
        ? parsed["lastCheckedAtMs"]
        : null;
    const stored = parsed["release"];
    let release: GitHubRelease | null = null;
    if (stored !== null && typeof stored === "object" && !Array.isArray(stored)) {
      const record = stored as Record<string, unknown>;
      const version = typeof record["version"] === "string" ? normalizeVersionTag(record["version"]) : null;
      if (version) {
        const rawURL = typeof record["htmlURL"] === "string" ? record["htmlURL"].trim() : "";
        release = {
          version,
          tag: typeof record["tag"] === "string" ? record["tag"] : `v${version}`,
          htmlURL: /^https:\/\/github\.com\/[^\s]+$/i.test(rawURL) ? rawURL : UPDATE_RELEASES_PAGE,
        };
      }
    }
    return { lastCheckedAtMs, release };
  } catch {
    return { lastCheckedAtMs: null, release: null };
  }
}

export function serializeUpdateState(state: UpdateState): string {
  return JSON.stringify({
    lastCheckedAtMs: state.lastCheckedAtMs,
    release: state.release ? { version: state.release.version, tag: state.release.tag, htmlURL: state.release.htmlURL } : null,
  });
}

export interface UpdateCheckResult {
  /** True when the network was actually contacted. */
  readonly requested: boolean;
  readonly release: GitHubRelease | null;
  /** True only for a successfully parsed release newer than the running version. */
  readonly updateAvailable: boolean;
  /** Attempt time to persist; `null` when the check was skipped. */
  readonly checkedAtMs: number | null;
  /** True when the request/parse failed (offline, rate limit, malformed JSON). */
  readonly failed: boolean;
}

export interface UpdateCheckOptions {
  readonly currentVersion: string;
  readonly enabled: boolean;
  readonly lastCheckedAtMs: number | null;
  readonly nowMs: number;
  /** Injected network call; resolves the HTTP status and body. */
  readonly requestLatest: () => Promise<{ readonly status: number; readonly body: string }>;
  /** Manual "立即检查" bypasses the once-a-day rule but never the off switch. */
  readonly force?: boolean;
}

export async function checkForUpdate(options: UpdateCheckOptions): Promise<UpdateCheckResult> {
  if (!options.enabled) {
    return { requested: false, release: null, updateAvailable: false, checkedAtMs: options.lastCheckedAtMs, failed: false };
  }
  if (!options.force && !shouldCheckForUpdate(options.nowMs, options.lastCheckedAtMs)) {
    return { requested: false, release: null, updateAvailable: false, checkedAtMs: options.lastCheckedAtMs, failed: false };
  }

  let release: GitHubRelease | null = null;
  let failed = false;
  try {
    const response = await options.requestLatest();
    if (response.status === 200) {
      release = parseLatestRelease(response.body);
      if (release === null) failed = true;
    } else {
      failed = true;
    }
  } catch {
    failed = true;
  }

  return {
    requested: true,
    release,
    updateAvailable: release !== null && isNewerVersion(release.version, options.currentVersion),
    checkedAtMs: options.nowMs,
    failed,
  };
}
