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
    "important": false,
    "url": "https://hassanfadi.github.io/FMoIP/"
  }
]
```

## Field notes

- `id` (required): stable unique id.
- `title` (required): short headline.
- `body` (required): message content shown to users.
- `publishedAt` (required): ISO-8601 UTC timestamp.
- `important` (optional): `true` shows a higher-priority icon.
- `url` (optional): reserved for future deep-link behavior.

## Publish flow

1. Edit `website/notifications.json`.
2. Add a new object at the top with a unique `id`.
3. Deploy website updates.
4. Users see a badge on the bell icon after app refresh/open.
