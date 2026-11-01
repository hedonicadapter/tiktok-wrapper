# ScrollGate

Classification: Internal

iOS wrapper around tiktok.com. Counts videos swiped; every N videos a native full-screen
*interrupt* blocks the feed until you deal with it (quiz, flashcard, prompt, read, timer, web).
Content comes from pluggable packs in the Files app. See `plan.md` for design and build order.

## Build

```sh
brew install xcodegen
xcodegen generate
open ScrollGate.xcodeproj
```

Set your team under Signing & Capabilities, run on a device (iOS 17+). Simulator works for
the overlay but TikTok's mobile site behaves differently there; test the feed on hardware.

Debug builds show a small `count/interval` badge top-right. Tap it for pack list, load errors,
"Fire now" and "Reload packs".

## Files app layout (`On My iPhone/ScrollGate/`)

```
config.json              interval, hardMode, pack weights, quietHours
hide-selectors.json      CSS selectors hidden on tiktok.com (app-nag banners)
packs/<id>/manifest.json
packs/<id>/items.json
```

Edits take effect when the app returns to foreground (or tap "Reload packs" in Debug).

### manifest.json

```json
{
  "id": "korkort",
  "title": "Körkortsteori",
  "kind": "quiz",                 // quiz | flashcard | prompt | read | timer | web
  "items": "items.json",          // optional, default items.json
  "strategy": "weighted-wrong",   // sequential | random | weighted-wrong | spaced
  "unlock": "correct"             // correct | any-answer | done
}
```

### items.json shapes

| kind | item |
|---|---|
| quiz | `{"id"?, "q", "answers": [...], "correct": 0, "explain"?}` |
| flashcard | `{"front", "back"}` |
| prompt | `{"text", "minChars": 40}` |
| read | `{"markdown", "minSeconds": 20}` or `{"file": "x.md", "minSeconds": 20}` |
| timer | `{"label", "seconds": 30}` |
| web | `{"url", "unlockAfterSeconds": 60}` |

A single object instead of an array is accepted (pack of one).

### config.json

```json
{
  "interval": 5,
  "hardMode": false,
  "packs": { "drivers-ed": 3, "stretch": 1, "blank-prompt": 1 },
  "quietHours": ["23:00", "07:00"]
}
```

- `packs`: weight per pack id. 0 parks it. Packs missing from the map get 0 (if the map is
  empty, every loaded pack gets 1).
- `hardMode`: forces `unlock: correct` on quiz/flashcard packs and removes the Skip button.
  Without hard mode, Skip appears after 30 s.
- `quietHours`: no interrupts between these times; counter resets instead.

## Unlock rules

- `correct` — quiz: wrong answer shows explanation, then "Try again". flashcard: "Didn't know"
  re-hides the card; you must then self-grade "Knew it".
- `any-answer` — any pick dismisses (still recorded right/wrong).
- `done` — prompt reaches minChars / read, timer, web timer reaches zero.

Pending interrupts are persisted: killing and relaunching the app brings the same interrupt back.

## Day 1 troubleshooting

- App-nag overlay blocks the feed: Safari on Mac → Develop → your iPhone → inspect, find its
  `data-e2e` or stable attribute, add to `hide-selectors.json`. Avoid hashed class names.
- Login loops: log in via Safari on the Mac, copy cookies with `WKHTTPCookieStore.setCookie`,
  or try `preferredContentMode = .desktop` on the web view's `defaultWebpagePreferences`.

## Distribution

Not App Store. Free Apple ID (7-day resign), AltStore/SideStore (auto-resign), or paid dev account.
