<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-white.png">
    <img src="docs/logo.png" alt="MeetPaw" width="320">
  </picture>
</p>

<h3 align="center">Instant meetings, from your Mac menu bar.</h3>
<p align="center">One-click Google Meet, Zoom &amp; Teams links, calendar sync, conflict detection, and global shortcuts for macOS.</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/SwiftUI-native-EA580C?logo=swift&logoColor=white">
  <img alt="Dependencies" src="https://img.shields.io/badge/dependencies-zero-2ea44f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

---

MeetPaw is a lightweight macOS menu-bar app that puts your meetings **one click away**. Spin up an instant **Google Meet, Zoom, or Microsoft Teams** link the moment you need it. The link is created, copied to your clipboard, and ready to share before you've switched windows. **No tabs, no digging, no friction.**

It also keeps your day in view: MeetPaw syncs with your **Google Calendar** and shows your upcoming meetings right in the menu bar, so you can **join with a single click** and get a **heads-up notification 15 minutes** before each one starts. Schedule new meetings complete with title, date, time, guests, and an auto-generated video link **without ever opening a browser**, and edit or delete them with a **swipe**.

Built natively in **SwiftUI with zero third-party dependencies**, MeetPaw is fast, private, and respectful of your Mac. Your account tokens stay in the **macOS Keychain** and never leave your device. The app talks only to Google, Zoom, and Microsoft directly. It's **free, open source under the MIT license**, and brings its own playful touch, right down to the paws that walk across your menu bar while a meeting spins up.

## Highlights

- ⚡ &nbsp;**One-click instant meetings** across Google Meet, Zoom, and Microsoft Teams
- 📅 &nbsp;**Upcoming meetings** from your Google Calendar, with one-click join
- ✏️ &nbsp;**Schedule, edit, and delete** meetings natively, no browser needed
- ⚠️ &nbsp;**Cross-calendar conflict detection** when you pick a time
- ⌨️ &nbsp;**Global shortcuts** (⌘⇧M / ⌘⇧Z / ⌘⇧T) to start a meeting from any app
- 🔔 &nbsp;**15-minute reminders** before every meeting
- 👥 &nbsp;**Multiple accounts** per provider (up to five each), merged into one list
- 🐾 &nbsp;**Launch at login**, Liquid Glass UI, and a menu-bar paw that actually walks
- 🔒 &nbsp;**Private by design**: tokens live only in your Keychain, no servers, no tracking
- 🆓 &nbsp;**Free and open source** under the MIT license

## Requirements

- macOS 14 or later (Apple silicon or Intel)
- Xcode / Swift toolchain (`swift --version`) to build from source
- Your own OAuth credentials for the providers you want to use (see below)

## Setup

MeetPaw talks to each provider as *your own* OAuth app, so you supply the credentials. Drop them into `~/.config/meetpaw/` (the app's "Add account" screen has an "Open credentials folder…" button that creates it for you).

### Google Meet

1. Open the [Google Cloud Console](https://console.cloud.google.com/) and create or pick a project.
2. **APIs & Services → Enable APIs** → enable **Google Calendar API** and **Google Meet API**.
3. **OAuth consent screen** → External. Add your Google account under **Test users** (or publish to Production to avoid the weekly re-login).
4. **Credentials → Create credentials → OAuth client ID → Desktop app**, then download the JSON.
5. Save it as `~/.config/meetpaw/credentials.json`.

Scopes: `calendar.events`, `meetings.space.created` (plus `openid`, `email` to show your address).

### Zoom

1. In the [Zoom Marketplace](https://marketplace.zoom.us/), **Develop → Build App → General App** (user-managed).
2. Set the OAuth redirect to the forwarding page `https://meetpaw.app/oauth/zoom.html` (Zoom requires HTTPS, so MeetPaw bounces the sign-in through a small page).
3. Add the scopes: `meeting:write:meeting`, `meeting:read:list_meetings`, `meeting:delete:meeting`, `user:read:user`.
4. Save `~/.config/meetpaw/zoom.json` as `{ "client_id": "…", "client_secret": "…" }`.

### Microsoft Teams

1. In [Microsoft Entra](https://entra.microsoft.com/), **App registrations → New registration** (multitenant).
2. Add a **Mobile and desktop** platform with redirect `http://localhost`, and enable **Allow public client flows**.
3. Add delegated Graph permissions: `OnlineMeetings.ReadWrite`, `Calendars.ReadWrite`, `User.Read`, `offline_access`. Grant admin consent if your org requires it.
4. Save `~/.config/meetpaw/microsoft.json` as `{ "client_id": "…" }` (public client, no secret).

## Build & run

```sh
./build.sh
open MeetPaw.app
```

A paw icon 🐾 appears in your menu bar. Click it, choose a provider, and sign in.

- **Left-click** the paw → instant meeting with your default provider.
- **Right-click** the paw → the drawer: upcoming meetings, schedule, accounts, settings.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| **⌘⇧M** | Instant Google Meet |
| **⌘⇧Z** | Instant Zoom meeting |
| **⌘⇧T** | Instant Microsoft Teams meeting |

Shortcuts work system-wide, from any app.

## Privacy

MeetPaw runs entirely on your Mac. Your access and refresh tokens are stored in the macOS **Keychain** and never leave your device. The app communicates only with Google, Zoom, and Microsoft, directly. There are no analytics, no tracking, and no servers in between. See the [Privacy Policy](https://meetpaw.app/privacy).

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
