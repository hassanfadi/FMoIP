# Website Notifications Feed

The app now reads notifications from a website JSON feed:

- URL: `https://hassanfadi.github.io/FMoIP/notifications.json`
- App state: `lib/state/app_notifications_state.dart`

## JSON format

Publish a JSON array sorted newest-first (the app also sorts by `publishedAt`):

```json
[
  {
    "id": "2026-05-01-app-updates",
    "title": "FMoIP update available",
    "body": "Message shown inside the app notifications panel.",
    "titleI18n": {
      "ar": "عنوان مترجم",
      "es": "Titulo traducido",
      "ru": "Переведенный заголовок",
      "zh": "已翻译标题"
    },
    "bodyI18n": {
      "ar": "رسالة مترجمة",
      "es": "Mensaje traducido",
      "ru": "Переведенное сообщение",
      "zh": "已翻译内容"
    },
    "publishedAt": "2026-05-01T08:00:00Z",
    "expiresAt": "2026-12-31T23:59:59Z",
    "priority": "normal",
    "popupOnOpen": false,
    "persistent": false,
    "platforms": ["all"],
    "versionTarget": {
      "mode": "all"
    },
    "url": "https://hassanfadi.github.io/FMoIP/"
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
- `popupOnOpen` (optional): when `true`, app can show this as a popup on launch.
- `persistent` (optional): when `true`, ignore does not permanently dismiss it.
- `platforms` (optional): target platforms, e.g. `["android"]`, `["ios"]`, or `["all"]`.
- `versionTarget` (optional): target app versions. If omitted, shown for all versions.
- `url` (optional): reserved for future deep-link behavior.

If localization maps are missing for the current app language, the app falls back to
the base `title` and `body`.

If `platforms` is omitted, the notification is shown on all platforms.

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

When `popupOnOpen` is `true`, the app can show a modal with 3 choices:

- **Interact now**: marks as read and opens `url` (if provided).
- **Remind later**: snoozes for a few hours.
- **Ignore**: dismisses permanently unless `persistent` is `true`.

## Reliability behavior

- If feed fetch fails or parsing fails, the app does **not** crash.
- Last successful feed is cached locally and used as fallback on next app start.
- Invalid items are skipped individually (with debug logs), while valid items still show.
- Failed refreshes are retried automatically with simple exponential backoff.
