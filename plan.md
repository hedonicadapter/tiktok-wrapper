# TikTok Quiz Wrapper (iOS) — plan.md

Classification: Internal

## Goal
iOS app that shows tiktok.com inside a web view, counts how many videos you've swiped past, and every N videos covers the screen with an *interrupt*: a piece of content you have to deal with before the feed comes back. What the content is — quiz question, flashcard, a page to read, a prompt to write a sentence, a stretch timer — is defined by pluggable content packs, not by the app. Driver's ed is just the first pack. TikTok's own code is never touched.

## What's already verified (no device needed)
- tiktok.com has a working mobile site: For You feed, swipe navigation, autoplay, search. Works in iPhone Safari today.
- Logged out you get a generic feed and a login wall after a while. Logged in you get your real algorithm. So: log in once inside the wrapper, keep cookies.
- The site uses `data-e2e="..."` attributes as stable hooks (e.g. `search-card-video`, `user-post-item`). CSS class names are hashed and change constantly — never key on them.
- WKWebView is the same engine as Safari. Default config blocks video autoplay and forces fullscreen playback; two flags fix that (see Config).
- WKWebView can run user-supplied JS on every page load and post messages back to Swift. That's the whole bridge.

## What can only be checked on a device (Day 1)
- Whether TikTok's "open in app" overlay on mobile web can be hidden with injected CSS, or whether it blocks the feed.
- Whether login/captcha works inside the wrapper or loops.
Both have fallbacks (below). Nothing else in this plan is uncertain.

## Stack
- Swift 5.10+, SwiftUI, WKWebView wrapped in `UIViewRepresentable`
- `WKUserScript` to inject JS, `WKScriptMessageHandler` to receive messages
- Content packs as folders of JSON (+ optional HTML/images) in the app's Documents dir, visible in the Files app → add/edit packs without rebuilding
- `UserDefaults` for counter + per-pack progress
- Xcode 16, iOS 17+

## Config (copy this, it's the non-obvious part)
```swift
let cfg = WKWebViewConfiguration()
cfg.allowsInlineMediaPlayback = true                       // no forced fullscreen
cfg.mediaTypesRequiringUserActionForPlayback = []         // autoplay works
cfg.websiteDataStore = .default()                          // cookies persist = stay logged in
cfg.userContentController.add(bridge, name: "tq")
cfg.userContentController.addUserScript(
  WKUserScript(source: feedObserverJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
let web = WKWebView(frame: .zero, configuration: cfg)
web.isInspectable = true                                   // debug from Safari on Mac
web.load(URLRequest(url: URL(string: "https://www.tiktok.com")!))
```
Do not set a custom User-Agent. Default WKWebView UA looks like Safari, which is what you want.

## Architecture
```
FeedView          SwiftUI, hosts WKWebView, shows InterruptOverlay as fullScreenCover
Bridge            WKScriptMessageHandler, receives {type:"video", id}
SwipeCounter      increments per unique video id, persisted, fires at N
InterruptOverlay  SwiftUI, interactiveDismissDisabled, renders whatever Interrupt it's given
PackStore         discovers packs in Documents/packs/, loads manifests
Scheduler         picks which pack fires next (rotation/weights), asks pack for next item
InterruptKinds/   one renderer per kind: Quiz, Flashcard, Prompt, Read, Timer, Web
Resources/        feed-observer.js, bundled starter pack (drivers-ed)
```
Overlay is native SwiftUI on top of the web view, not injected into TikTok's page. TikTok's JS can't see it, remove it, or scroll under it.

## Content model
Everything the overlay shows is an `Interrupt`. The app knows a fixed set of *kinds*; packs supply items of those kinds.

```swift
protocol InterruptPack {
  var id: String { get }
  func next(progress: PackProgress) -> Interrupt      // pack decides ordering/spacing
  func record(_ item: Interrupt, result: Result)      // pack updates its own stats
}
enum Interrupt {
  case quiz(q: String, answers: [String], correct: Int, explain: String?)
  case flashcard(front: String, back: String)        // reveal, then self-grade
  case prompt(text: String, minChars: Int)           // type something; unlocks at minChars
  case read(markdown: String, minSeconds: Int)       // read; unlocks after timer
  case timer(label: String, seconds: Int)            // stretch, breathe, look away
  case web(url: URL, unlockAfterSeconds: Int)        // Anki web, Duolingo, your own page
}
enum Result { case correct, wrong, done, skipped }
```
Adding a new kind = one enum case + one SwiftUI view. Adding content = a folder.

### Pack format (`Documents/packs/<id>/manifest.json`)
```json
{
  "id": "korkort",
  "title": "Körkortsteori",
  "kind": "quiz",
  "items": "items.json",
  "strategy": "weighted-wrong",     // or "sequential", "random", "spaced"
  "unlock": "correct"               // or "any-answer", "done"
}
```
`items.json` is an array in the shape of that kind. `strategy` and `unlock` are picked from a fixed list the app implements; packs don't carry code.
For `web` and `read` kinds, items can be a single URL/markdown file — pack of one.

### Scheduler config (`Documents/config.json`)
```json
{
  "interval": 5,
  "hardMode": false,
  "packs": { "korkort": 3, "spanish-flashcards": 2, "stretch": 1 },   // weights
  "quietHours": ["23:00", "07:00"]
}
```
Weights decide which pack fires next. Set a pack to 0 to park it.

### Starter packs shipped in bundle, copied to Documents on first launch
- `drivers-ed` (quiz) — the original use case
- `stretch` (timer) — 30 s, no content needed
- `blank-prompt` (prompt) — "write one sentence about anything", 40 chars

## feed-observer.js (what it does)
1. `MutationObserver` on `document.body`: every time a new `<video>` element appears, attach an `IntersectionObserver` (threshold 0.6) to it.
2. When a video becomes ≥60% visible, take its `src` (or `currentSrc`) as id. If unseen, send `window.webkit.messageHandlers.tq.postMessage({type:"video", id})`. Dedup set + 400 ms debounce kills double-fires from rubber-banding.
3. Define `window.__tq = { pause(){ document.querySelectorAll('video').forEach(v=>v.pause()) }, resume(){ /* play the most visible one */ } }`. Swift calls these via `evaluateJavaScript` when quiz opens/closes.
4. Inject CSS to hide app-nag elements. Selectors live in a JSON array so you can edit without touching JS.

Keying on `<video>` instead of a feed-item selector means it works even if TikTok renames every container tomorrow. One video per screen on mobile feed = one swipe.

## Build order

### Day 1 — feed works in the wrapper
Empty app with the Config above. Open it, log in, scroll 20 videos.
Done when: feed scrolls, videos autoplay inline, you're still logged in after killing the app.
If the app-nag overlay blocks the feed → inspect it (Safari → Develop → your iPhone), add its selector to the hide list.
If login loops → log in via Safari on the Mac, copy cookies in with `WKHTTPCookieStore.setCookie`. Or try `web.configuration.defaultWebpagePreferences.preferredContentMode = .desktop`.

### Day 2 — counting
Add feed-observer.js + Bridge. Print every message.
Done when: swipe 30 videos by hand, counter reads 30 ±1.

### Day 3 — overlay + one kind
At N: `__tq.pause()`, present InterruptOverlay with a hardcoded `.quiz`. Unlock → dismiss, `__tq.resume()`, reset counter.
Done when: you cannot get back to the feed by scrolling, backgrounding, or relaunching without satisfying the unlock rule.

### Day 4 — packs
PackStore reads `Documents/packs/*/manifest.json`. Scheduler picks by weight. Implement `weighted-wrong` strategy (weight = `1 + 2*wrongCount - 0.5*correctStreak`, min 0.2) and `sequential`. Ship drivers-ed as first pack.
Done when: drop a new folder in via Files app, kill/relaunch, it fires. Wrong answers recur within ~5 interrupts.

### Day 5 — remaining kinds
Flashcard, Prompt, Read, Timer, Web renderers. Each is a small SwiftUI view + unlock rule.
Done when: `stretch` and `blank-prompt` starter packs work; a `web` pack pointing at any URL loads and unlocks after its timer.

### Later (optional)
Settings UI for config.json. Stats per pack. `spaced` strategy (SM-2). Pull packs from a URL / iCloud folder. Export stats.

## Known risks
| Risk | Plan |
|---|---|
| App-nag overlay on mobile web | CSS hide list, editable without rebuild |
| Login wall / captcha inside WKWebView | Cookie import from Mac Safari; desktop content mode |
| TikTok flags web usage, logs you out | Low volume personal use. Re-login. Accept. |
| `<video>` src is blob URL that changes per render | Fall back to closest `[data-e2e]` ancestor's attribute, then element index |
| Pack JSON malformed | Validate on load, skip pack, show its error in Settings. Never crash the feed. |
| `web` kind loads a site that itself redirects/nags | It's your pack, your problem. Same CSS-hide mechanism available per pack. |
| Can't put it on App Store | Not trying. See Distribution. |

## Distribution
- Free Apple ID + Xcode: resign every 7 days. Works, annoying.
- AltStore/SideStore: auto-resigns over Wi-Fi. Free. Probably the right answer.
- Paid dev account ($99/yr): resign once a year.

## Repo layout
```
scrollgate/
  App/         FeedView.swift, ScrollGateApp.swift
  Bridge/      Bridge.swift, SwipeCounter.swift
  Interrupts/  Interrupt.swift, InterruptOverlay.swift, Kinds/{Quiz,Flashcard,Prompt,Read,Timer,Web}View.swift
  Packs/       InterruptPack.swift, PackStore.swift, Scheduler.swift, Strategies/
  Resources/   feed-observer.js, hide-selectors.json, starter-packs/{drivers-ed,stretch,blank-prompt}/
  plan.md
```

## Done means
Open app, scroll For You, every Nth video an interrupt blocks the feed until its unlock rule is met. Which interrupt is decided by config + packs you can edit in the Files app without touching Xcode. Progress survives relaunch, runs a week without code changes.
