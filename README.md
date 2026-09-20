# My Lecto

A personal lecture recorder for Android. It records offline, keeps everything on
the phone, and makes notes by handing the audio to whichever AI app you already
use.

There is no backend, no account and no API key. Clone it and build it.

## How it works

1. **Record** a lecture. Audio is written in chunks as it goes, so a crash or a
   force-close can only ever cost the chunk in progress.
2. **Share to your AI.** The chunks are merged into a single `.m4a` and sent to
   Claude, Gemini or Grok through the normal Android share sheet, along with a
   `prompt.txt` telling it what notes to write.
3. **Paste the reply back.** You review what was parsed before it saves, then it
   becomes structured notes — a summary, key concepts, tickable tasks and
   deadlines.

Nothing is uploaded anywhere. The app does not request the `INTERNET`
permission, so it cannot phone home even by accident.

## Build

```bash
flutter pub get
flutter build apk --release
```

The APK lands in `build/app/outputs/flutter-apk/app-release.apk`.

To run it on a connected device:

```bash
flutter run --release
```

## What's in it

- Chunked recording with a foreground service, so it keeps going with the screen
  off or the app in the background
- Recovery at launch for recordings cut short by a crash
- An 8-hour session cap, warning at 7h45m
- HE-AAC at 24kbps mono — about 33MB for a three-hour lecture
- Merging chunks into one file natively (`MediaMuxer`), without re-encoding
- Notes parsing that copes with AI apps stripping markdown when you copy
- PDF export, an audio player, in-transcript search, subjects, and sorting

## Things worth knowing

**Your AI app decides the real limits.** Gemini takes up to 3 hours of audio on
a paid plan and 10 minutes on the free one. Nothing this app does can change
that.

**Long lectures get notes but no transcript.** Above 30 minutes the prompt stops
asking for one, because a three-hour transcript will not fit in a single reply
and trying starves the notes of detail. The threshold lives in
`AiShareService.transcriptLimit`.

**ChatGPT cannot receive audio.** It registers for PDFs and text only, so it
will not appear in the share sheet for a recording.

## Handy while developing

Reproduce a long lecture's chunk count in minutes instead of hours:

```bash
flutter run --dart-define=CHUNK_MINUTES=1
```

## Layout

```
lib/
  core/          services, theme, routing, errors
  features/
    home/        landing screen
    subjects/    subjects and their recordings
    recording/   capture, storage, playback, notes
    transcript/  the full list of recordings
    settings/
android/app/src/main/kotlin/com/lecto/lecto/
  AudioMerger.kt   joins chunks into one file
```

Tests: `flutter test`
