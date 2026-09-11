# Scientist Outreach Portal — field app

The desktop app Antarctic field scientists use to file reports for the
**Integrated Polar Science Outreach Portal** (SIH 2026, PS 26063 — MoES / NCPOR).

A scientist records what they did — station, activity, position, weather,
measurements, notes, photos, a voice memo, data files — and the app keeps it
on the machine until there is a connection, then sends it to the portal.
There, an admin screens it for personal and sensitive content before it goes
anywhere else.

## Run it (Windows 10 / 11, 64-bit)

No Flutter, no installer, nothing else to install:

1. Download or clone this repository.
2. Open **`ScientistOutreachPortal-Windows`**.
3. Run **`ScientistOutreachPortal.exe`**.

Keep the whole folder together — the `.exe` needs the `.dll` files and the
`data` folder beside it. The Microsoft Visual C++ runtime
(`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`) is included, so it
runs on a fresh Windows install too. It is a Windows app: it does not run on
macOS, Linux or phones.

On first launch you create a profile (name, institute ID, station) and a
4-digit PIN, which unlocks the app from then on.

## Working offline

The app is built to be used with no connection at all:

- **Reports are stored on the machine** in a SQLite database in your
  Documents folder (`Documents\iia_scientist.db`), so filing and reading
  reports work offline.
- **Attachments are copied into the app** (`Documents\iia_scientist_media\`)
  when a report is saved, so a photo on a camera card or a file on a USB stick
  can be removed afterwards without breaking the upload.
- **Each report shows QUEUED** until it has been sent, then **SYNCED TO
  PORTAL**.
- **It sends by itself** — when the app starts, straight after a report is
  saved, and whenever the connection comes back. Nothing needs pressing.
- **If the portal refuses a report, or the connection drops mid-upload**, the
  report stays queued, says why, and is retried.

What needs a connection: sending reports, and the *Incoming Transmissions*
tab (questions from students), which reads live from the portal.

## Limits the portal enforces

- At most **5 photos** per report (the app stops at 5).
- Field notes of at most **2,000 characters** (the app counts down).

## Build from source

Needs the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)
and Visual Studio with the *Desktop development with C++* workload.

```
flutter pub get
flutter test
flutter build windows --release
```

The build lands in `build\windows\x64\runner\Release\`.

## How it connects

- Firebase project `indiainantartica` — anonymous sign-in, Firestore
  collection `dispatches`, Storage under `dispatches/<uid>/<report id>/`.
- Every report arrives in the portal as `raw`, visible only to admins, who
  screen it before it reaches the publishers or the public website.
- `lib/firebase_options.dart` holds the Firebase *client* configuration. That
  key is public by design — it identifies the project; the portal's security
  rules decide what any client may read or write.
- The field vocabulary in `lib/models/field_vocabulary.dart` mirrors the
  portal's `types.ts` exactly; the portal's test suite checks the two match.
