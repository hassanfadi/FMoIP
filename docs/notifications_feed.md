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
    "publishedAt": "2026-05-01T08:00:00Z",
    "expiresAt": "2026-12-31T23:59:59Z",
    "priority": "normal",
    "popupOnOpen": false,
    "persistent": false,
    "url": "https://hassanfadi.github.io/FMoIP/"
  }
]
```

## Field notes

- `id` (required): stable unique id.
- `title` (required): short headline.
- `body` (required): message content shown to users.
- `publishedAt` (required): ISO-8601 UTC timestamp.
- `expiresAt` (optional): ISO-8601 UTC timestamp; once reached, the app hides that notification.
- `priority` (optional): one of `low`, `normal`, `high`, `urgent`.
- `popupOnOpen` (optional): when `true`, app can show this as a popup on launch.
- `persistent` (optional): when `true`, ignore does not permanently dismiss it.
- `url` (optional): reserved for future deep-link behavior.

## Publish flow

1. Edit `website/notifications.json`.
2. Add a new object at the top with a unique `id`.
3. Deploy website updates.
4. Users see an unread-count badge on the bell icon after app refresh/open.

## Popup behavior

When `popupOnOpen` is `true`, the app can show a modal with 3 choices:

- **Interact now**: marks as read and opens `url` (if provided).
- **Remind later**: snoozes for a few hours.
- **Ignore**: dismisses permanently unless `persistent` is `true`.
