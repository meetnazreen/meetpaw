<p align="center">
  <img src="docs/icon.png" alt="MeetPaw" width="120" height="120">
</p>

<h1 align="center">MeetPaw</h1>

A tiny macOS menu-bar app for Google Meet. Spin up an instant meeting link in
one click, and join your upcoming Google Calendar meetings without digging
through tabs.

- **New instant meeting** — creates a fresh Meet link (Google Meet REST API),
  copies it to the clipboard, and opens it.
- **Upcoming meetings** — lists Calendar events with a Meet link in the next
  24 hours; click to join.

Native SwiftUI `MenuBarExtra`, no third-party dependencies.

## Requirements

- macOS 14+
- Xcode / Swift toolchain (`swift --version`)
- A Google Cloud project with OAuth credentials (see below)

## Google Cloud setup (one-time)

MeetPaw talks to Google as *your own* OAuth app, so you supply the credentials:

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and
   create (or pick) a project.
2. **APIs & Services → Enable APIs** → enable both:
   - Google Calendar API
   - Google Meet API
3. **OAuth consent screen** → External. Add your Google account under
   **Test users**.
4. **Credentials → Create credentials → OAuth client ID → Desktop app.**
5. Download the JSON. Save it as:

   ```
   ~/.config/meetpaw/credentials.json
   ```

   (The app's "Open credentials folder…" button creates this folder for you.)

### Scopes used

- `calendar.events` — read upcoming meetings, and create a Meet-linked event
  as a fallback when the Meet API isn't available on your account
- `meetings.space.created` — create instant meetings

## Build & run

```sh
./build.sh
open MeetPaw.app
```

A paw icon 🐾 appears in your menu bar. Click it → **Sign in with Google**.

## A note on the "testing" OAuth mode

While your consent screen is in **Testing** status, Google expires the refresh
token after **7 days**, so you'll be asked to sign in again about weekly.
Publishing the app to **Production** (it stays unverified, with a warning
screen, which is fine for personal/open-source use under 100 users) removes the
weekly re-login. MeetPaw handles the expiry gracefully — it just drops you back
to the sign-in screen.

## Development

```sh
swift run MeetPaw --selftest   # runs the event-parsing self-check
swift build                    # debug build
```

## Author

Created and maintained by **Nazreen** &lt;nazreenexe@outlook.com&gt;
([@meetnazreen](https://github.com/meetnazreen)).

## License

MIT — see [LICENSE](LICENSE).
