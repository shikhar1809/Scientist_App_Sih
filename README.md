# Scientist Outreach Portal — field app

The app Antarctic field scientists use to file reports for the
**Integrated Polar Science Outreach Portal** (SIH 2026, PS 26063 — MoES / NCPOR).

A scientist records what they did — station, activity, position, weather,
measurements, notes, photos, a voice memo, data files — and the app keeps it
on the device until there is a connection, then sends it to the portal.
There, an admin screens it for personal and sensitive content before it goes
anywhere else.

## Run it

### Windows 10 / 11, 64-bit

No Flutter, no installer, nothing else to install:

1. Download or clone this repository.
2. Double-click **`Run Scientist Outreach Portal.bat`**
   (or open `ScientistOutreachPortal-Windows` and run
   `ScientistOutreachPortal.exe`).

Keep the whole folder together — the `.exe` needs the `.dll` files and the
`data` folder beside it. The Microsoft Visual C++ runtime
(`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`) is included, so it
runs on a fresh Windows install too.

### Android 5.0 and later

Copy **`ScientistOutreachPortal-Android.apk`** to the phone or tablet and open
it. Android asks once to allow installing apps from that source (the app is
not on the Play Store). On a phone the app switches to a one-pane layout: the
menu is behind the ☰ button and a report opens full screen.

On first launch you create a profile (name, institute ID, station) and a
4-digit PIN, which unlocks the app from then on.

## Working offline — and over a station's satellite link

Indian stations (Maitri, Bharati, Himadri) reach the outside world over a
satellite link: slow, expensive per megabyte, and liable to drop. The app is
built for that, and for no connection at all:

- **Reports are stored on the device** in a SQLite database, so filing and
  reading reports work offline.
- **Attachments are copied into the app** when a report is saved, so a photo
  on a camera card or a file on a USB stick can be removed afterwards.
- **Photos are shrunk before sending** — at most 2048 px on the long side,
  JPEG, location and camera data (EXIF) stripped. A 6 MB camera photo goes
  up as roughly 0.5–1 MB.
- **Every file goes up resumably, in 512 KB pieces.** If the link drops
  halfway, the next attempt continues from the last piece that arrived —
  nothing already sent is sent again.
- **It sends by itself** — when the app starts, straight after a report is
  saved, when the connection comes back, and every two minutes while
  anything is still queued. Nothing needs pressing.
- **Each report shows QUEUED**, then **SENDING** with progress
  ("Photo 2 of 4 · 60 %"), then **SYNCED TO PORTAL**.
- **If the portal refuses a report**, it stays queued and says why.

What needs a connection: sending reports, and the *Incoming Transmissions*
tab (questions from students), which is refreshed every two minutes.

## Limits the portal enforces

- At most **5 photos** per report (the app stops at 5).
- Field notes of at most **2,000 characters** (the app counts down).

## Build from source

Needs the [Flutter SDK](https://docs.flutter.dev/get-started/install);
for Windows, Visual Studio with *Desktop development with C++*; for Android,
the Android SDK and JDK 17.

```
flutter pub get
flutter test
flutter build windows --release
flutter build apk --release
```

The builds land in `build\windows\x64\runner\Release\` and
`build\app\outputs\flutter-apk\app-release.apk`.

## How it connects

- Firebase project `indiainantartica`, spoken to over plain HTTPS (the
  Firebase REST APIs) rather than the Firebase SDKs — so the same code runs
  on Windows and Android, and the upload can be resumed piece by piece.
- Anonymous sign-in; the session is kept on the device, so the same identity
  survives restarts.
- Firestore collection `dispatches`; Storage under
  `dispatches/<uid>/<report id>/`.
- Every report arrives in the portal as `raw`, visible only to admins, who
  screen it before it reaches the publishers or the public website.
- `lib/portal_config.dart` holds the Firebase *client* configuration. That
  key is public by design — it identifies the project; the portal's security
  rules decide what any client may read or write.
- The field vocabulary in `lib/models/field_vocabulary.dart` mirrors the
  portal's `types.ts` exactly; the portal's test suite checks the two match.
