# Website Notifications Feed

The app reads notifications from a website JSON feed:

- URL: `https://hassanfadi.github.io/FMoIP/notifications.json`
- App state: `lib/state/app_notifications_state.dart`
- In-app actions: `lib/services/notification_action_handler.dart`

## JSON format

Publish a JSON array (the app sorts by `publishedAt`, newest first):

```json
[
  {
    "id": "2026-05-02-catalog-example",
    "title": "Switch station catalog to FMoIP",
    "body": "Tap Interact now to apply the FMoIP catalog and review Settings.",
    "titleI18n": { "ar": "…", "es": "…", "ru": "…", "zh": "…" },
    "bodyI18n": { "ar": "…", "es": "…", "ru": "…", "zh": "…" },
    "publishedAt": "2026-05-02T14:00:00Z",
    "expiresAt": "2027-12-31T23:59:59Z",
    "priority": "high",
    "popupOnOpen": true,
    "persistent": false,
    "platforms": ["all"],
    "versionTarget": { "mode": "all" },
    "action": "write",
    "highlight": true,
    "write": {
      "catalogSource": "fmoipMirror"
    }
  },
  {
    "id": "2026-05-01-store",
    "title": "Update available",
    "body": "Get the latest version from the store.",
    "publishedAt": "2026-05-01T08:00:00Z",
    "expiresAt": "2026-12-31T23:59:59Z",
    "priority": "normal",
    "popupOnOpen": false,
    "persistent": false,
    "platforms": ["all"],
    "versionTarget": { "mode": "lt", "version": "1.0.0+45" },
    "url": "https://play.google.com/store/apps/details?id=com.fmoip.app"
  }
]
```

## Field notes

- `id` (required): stable unique id.
- `title` (required): short headline.
- `body` (required): message content shown to users.
- `titleI18n` (optional): localized titles by language code (e.g. `ar`, `es`, `ru`, `zh`).
- `bodyI18n` (optional): localized body text by language code.
- `publishedAt` (required): ISO-8601 UTC timestamp.
- `expiresAt` (optional): ISO-8601 UTC timestamp; once reached, the app hides that notification.
- `priority` (optional): one of `low`, `normal`, `high`, `urgent`.
- `popupOnOpen` (optional): when `true`, the app can show this item as a modal on launch (see [Popup behavior](#popup-behavior)).
- `persistent` (optional): when `true`, ignore does not permanently dismiss it.
- `platforms` (optional): target platforms, e.g. `["android"]`, `["ios"]`, or `["all"]`.
- `versionTarget` (optional): target app versions. If omitted, shown for all versions.

If localization maps are missing for the current app language, the app falls back to the base `title` and `body`.

If `platforms` is omitted, the notification is shown on all platforms.

### `url` and the FMoIP notification “protocol”

The app treats notification behavior in two layers:

1. **External link (`url`)** — If `url` is present and uses **`http` or `https`**, **Interact now** (and tapping a row in the notifications sheet) opens that URL in an **external** browser/app. Typical uses: Play Store, privacy page, your website. In this case, **in-app `action` / `write` fields are not run** for that interaction (the external URL wins first).

2. **In-app FMoIP actions** — Controlled by JSON fields on the same item (no separate `fmoip://` URI is required today):

   | Field | Meaning |
   |--------|--------|
   | `action` | `"read"` (default) or `"write"`. **Read** = show UI only (scroll/highlight). **Write** = apply allowlisted settings, then optionally open Settings. |
   | `highlight` | `true` / `false`. For **`write`**, after applying changes, scrolls to the **Station catalog** row in Settings and can briefly emphasize it. For **`read`** with `highlight: true`, opens Settings and scrolls/highlights that row without changing prefs. |
   | `write` | Object with **allowlisted** keys. Supported today: **`catalogSource`** → `"fmoipMirror"` or `"radioBrowser"` (variants like `fmoip` / `radio_browser` are accepted). |

This is the **FMoIP notification protocol** in the feed: **external URLs for the web/store**, plus **`action` / `highlight` / `write`** for **trusted in-app behavior** (validated in code—do not add arbitrary keys without an app update).

**Examples**

- **Store link only:** set `url` to `https://…`; omit `action`/`write` or leave `action` as `read`.
- **Switch catalog to FMoIP mirror:** omit `url` (or use only non-http links later); set `"action": "write"`, `"highlight": true`, `"write": { "catalogSource": "fmoipMirror" }`.
- **Point users at Settings without changing prefs:** `"action": "read"`, `"highlight": true` (no `write` object).

Future versions may add a custom scheme (e.g. `fmoip://settings/...`) parsed into the same handler; the feed fields above remain the source of truth for what ships today.

### `versionTarget` modes

Use semantic app versions with build number, e.g. `1.0.0+45`.

- `{"mode":"all"}` → all app versions
- `{"mode":"eq","version":"1.0.0+45"}` → only this exact version
- `{"mode":"lt","version":"1.0.0+45"}` / `lte` → lower / lower-or-equal
- `{"mode":"gt","version":"1.0.0+45"}` / `gte` → higher / higher-or-equal
- `{"mode":"range","minVersion":"1.0.0+40","maxVersion":"1.0.0+45"}` → inclusive range

## Publish flow

1. Edit `website/notifications.json`.
2. Add a new object at the top with a unique `id`.
3. Run `docs/safe_messaging_checklist.md` before publishing (policy, billing, links, and targeting checks).
4. Deploy website updates.
5. Users see an unread-count badge on the bell icon after app refresh/open.

## Popup behavior

When `popupOnOpen` is `true`, the app can show a modal with three choices:

- **Interact now**: marks as read, then runs the [FMoIP notification protocol](#url-and-the-fmoip-notification-protocol): opens **`http`/`https` `url`** externally if present; otherwise applies **`write`** and/or opens **Settings** for **`read`**/**`write`** as configured.
- **Remind later**: snoozes for a few hours.
- **Ignore**: dismisses permanently unless `persistent` is `true`.

Tapping a notification row in the bell sheet uses the same action logic as **Interact now** (and marks that item read).

## Reliability behavior

- If feed fetch fails or parsing fails, the app does **not** crash.
- Last successful feed is cached locally and used as fallback on next app start.
- Invalid items are skipped individually (with debug logs), while valid items still show.
- Failed refreshes are retried automatically with simple exponential backoff.
