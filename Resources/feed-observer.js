// feed-observer.js — injected into tiktok.com at document end, main frame only.
// Reports each video that becomes >=60% visible to Swift via webkit.messageHandlers.tq.
// Never touches TikTok's own code; only observes DOM + injects hide CSS.
(function () {
  if (window.__tq) return; // already installed (SPA navigation re-runs scripts)

  // Replaced by Swift with contents of hide-selectors.json before injection.
  var HIDE_SELECTORS = __HIDE_SELECTORS__;
  // Nag dialogs to dismiss the way a user would ("Not now", "Continue on web").
  var CLICK_SELECTORS = __CLICK_SELECTORS__;
  var THRESHOLD = 0.6;
  var DEBOUNCE_MS = 400;

  function post(msg) {
    try {
      window.webkit.messageHandlers.tq.postMessage(msg);
    } catch (e) { /* not in WKWebView */ }
  }
  function log(s) { post({ type: 'log', msg: String(s) }); }

  // --- hide app-nag elements ------------------------------------------------
  function installHideCSS() {
    if (!HIDE_SELECTORS || !HIDE_SELECTORS.length) return;
    var style = document.createElement('style');
    style.id = '__tq_hide';
    style.textContent = HIDE_SELECTORS.join(',\n') + ' { display: none !important; }';
    (document.head || document.documentElement).appendChild(style);
  }

  // --- desktop feed: make it look like the app ----------------------------
  // TikTok's desktop feed sizes each item by the video's aspect ratio and left-aligns it,
  // leaving a dead strip on the right on a phone. Fill the column instead; portrait videos
  // cover the screen like the app, landscape ones letterbox. Only applies when the desktop
  // feed is detected (html.tq-desktop), keyed on data-e2e hooks, not hashed class names.
  var DESKTOP_CSS = [
    'html.tq-desktop, html.tq-desktop body { background: #000 !important; overflow-x: hidden !important; }',
    '.tq-desktop [data-e2e="anchoring-player-column"] { flex: 1 1 auto !important; width: auto !important; max-width: none !important; margin: 0 !important; padding: 0 !important; }',
    '.tq-desktop [data-e2e="anchoring-player-column"] > * { width: 100% !important; max-width: none !important; }',
    '.tq-desktop [data-e2e="recommend-list-item-container"] { width: 100% !important; max-width: none !important; padding: 0 !important; margin: 0 !important; justify-content: stretch !important; }',
    '.tq-desktop [data-e2e="recommend-list-item-container"] > * { width: 100% !important; max-width: none !important; }',
    '.tq-desktop [data-e2e="feed-video"] { width: 100% !important; max-width: none !important; height: 100% !important; aspect-ratio: auto !important; border-radius: 0 !important; background: #000 !important; }',
    '.tq-desktop [data-e2e="feed-video"] video { position: absolute !important; inset: 0 !important; transform: none !important; translate: none !important; width: 100% !important; height: 100% !important; max-width: none !important; max-height: none !important; object-fit: contain !important; }',
    '.tq-desktop [data-e2e="feed-video"] video[data-tq-fit="cover"] { object-fit: cover !important; }',
    '.tq-desktop [data-e2e="anchoring-ambient"] { display: none !important; }',
    '.tq-desktop [data-e2e="anchoring-scroll-controls"] { opacity: 0 !important; pointer-events: none !important; }'
  ].join('\n');

  function applyDesktopMode() {
    var isDesktop = !!document.querySelector('[data-e2e="anchoring-player-column"]');
    var root = document.documentElement;
    if (isDesktop && !root.classList.contains('tq-desktop')) {
      root.classList.add('tq-desktop');
      var st = document.createElement('style');
      st.id = '__tq_desktop';
      st.textContent = DESKTOP_CSS;
      (document.head || root).appendChild(st);
      log('desktop layout fixes on');
    }
    if (!isDesktop) return;
    // Fill the screen like the app only when that crops little; otherwise letterbox so
    // burnt-in captions stay whole (beside the rail the space is much narrower than 9:16).
    document.querySelectorAll('[data-e2e="feed-video"] video').forEach(function (v) {
      if (!v.videoWidth) return;
      var box = v.parentElement.getBoundingClientRect();
      if (!box.width || !box.height) return;
      var va = v.videoWidth / v.videoHeight, ba = box.width / box.height;
      var crop = 1 - Math.min(va, ba) / Math.max(va, ba);
      var fit = crop <= 0.12 ? 'cover' : 'contain';
      if (v.getAttribute('data-tq-fit') !== fit) v.setAttribute('data-tq-fit', fit);
    });
    idleResnap();
  }

  // Tapping a video on a profile opens TikTok's desktop "browse" dialog: a side-by-side layout
  // whose comments/like column lands off-screen on a phone, with no top inset. Loading the same
  // URL as a page gives the feed layout instead (side buttons, fits). One reload per URL.
  function escapeBrowseDialog() {
    var bv = document.querySelector('[role="dialog"] [data-e2e="browse-video"]');
    if (!bv || !/\/video\/\d+/.test(location.pathname)) return;
    var key = '__tq_browse_' + location.pathname;
    try { if (sessionStorage.getItem(key)) return; sessionStorage.setItem(key, '1'); } catch (e) { return; }
    log('browse dialog → reload as page ' + location.pathname);
    location.replace(location.href);
  }

  // After the column resizes (comments panel opened/closed, rotation) the snap list can be
  // left between items. Re-align the item nearest the top once things settle.
  var resnapTimer = null, touching = false;
  function resnap() {
    if (touching) return;
    var item = null, best = Infinity;
    document.querySelectorAll('[data-e2e="recommend-list-item-container"]').forEach(function (a) {
      var list = a.parentElement; if (!list) return;
      var d = Math.abs(a.getBoundingClientRect().top - list.getBoundingClientRect().top);
      if (d < best) { best = d; item = a; }
    });
    if (item && best > 4) { item.scrollIntoView({ block: 'start' }); log('re-snapped feed (' + Math.round(best) + 'px off)'); }
  }
  // Also catch misalignment without a resize (e.g. comments closed): when the list has been
  // still for a moment and sits between items, re-align.
  var lastTouchEnd = 0, lastListTop = null;
  function idleResnap() {
    if (touching || Date.now() - lastTouchEnd < 1200) return;
    var a = document.querySelector('[data-e2e="recommend-list-item-container"]');
    var list = a && a.parentElement; if (!list) return;
    var st = list.scrollTop;
    var still = lastListTop === st; lastListTop = st;
    if (!still) return;
    var off = Infinity;
    list.querySelectorAll('[data-e2e="recommend-list-item-container"]').forEach(function (it) {
      off = Math.min(off, Math.abs(it.getBoundingClientRect().top - list.getBoundingClientRect().top));
    });
    if (off > 12 && off !== Infinity) resnap();
  }
  var ro = ('ResizeObserver' in window) ? new ResizeObserver(function () {
    clearTimeout(resnapTimer); resnapTimer = setTimeout(resnap, 300);
  }) : null;
  function watchColumn() {
    var col = document.querySelector('[data-e2e="anchoring-player-column"]');
    if (ro && col && !col.__tqWatched) { col.__tqWatched = true; ro.observe(col); }
  }
  document.addEventListener('touchstart', function () { touching = true; }, { passive: true, capture: true });
  document.addEventListener('touchend', function () {
    lastTouchEnd = Date.now();
    setTimeout(function () { touching = false; }, 400);
  }, { passive: true, capture: true });

  // --- auto-dismiss nag dialogs -------------------------------------------
  var clickedRecently = 0;
  function dismissNags() {
    if (!CLICK_SELECTORS || !CLICK_SELECTORS.length) return;
    var now = Date.now();
    if (now - clickedRecently < 500) return;
    for (var i = 0; i < CLICK_SELECTORS.length; i++) {
      var el = document.querySelector(CLICK_SELECTORS[i]);
      // offsetParent is null inside position:fixed overlays; use client rects instead.
      if (el && el.getClientRects().length > 0) {
        clickedRecently = now;
        try { el.click(); log('dismissed ' + CLICK_SELECTORS[i]); } catch (e) {}
        return;
      }
    }
  }

  // --- generic nag handling -------------------------------------------------
  // Any overlay/dialog/sheet whose text pushes the app gets dismissed like a user would:
  // tap its "Not now"/close control, else hide it and its dim mask. Login forms are left alone.
  var NAG_TEXT = /öppna (tiktok|appen)|open (the )?(tiktok|app)|i appen|in the app|hämta appen|skaffa appen|get (the )?(full )?(tiktok )?app|ladda ner|download|fortsätt i appen|continue in (the )?app|watch (more )?on tiktok|titta (vidare |mer )?(på|i) (tiktok|appen)|se (fler|mer)( videor)? i appen|app experience|appupplevelse|använd appen|use the app|bättre i appen|better in the app/i;
  var DISMISS_TEXT = /^(inte nu|not now|fortsätt på webben|fortsätt på webbplatsen|continue on web|continue (in|on) (the )?browser|fortsätt i webbläsaren|avbryt|cancel|stäng|close|nej tack|no thanks|kanske senare|maybe later|×|✕|x)$/i;
  var WEB_CHOICE = /^(fortsätt på webben|fortsätt på webbplatsen|continue on web|continue (in|on) (the )?browser|fortsätt i webbläsaren|inte nu|not now)$/i;
  var DIALOG_SEL = '[role="dialog"],[aria-modal="true"],.tt-sheet__container,[class*="Modal"],[class*="modal"],[class*="Popup"],[class*="popup"],[class*="Sheet"],[class*="sheet"],[class*="Drawer"],[class*="Guide"],[class*="CTA"],[data-e2e*="popup"],[data-e2e*="modal"],[data-e2e*="cta"]';
  var handled = new WeakMap(); // el -> time first handled

  function isVisible(el) {
    if (!el || !el.getClientRects().length) return false;
    var cs = getComputedStyle(el);
    return cs.display !== 'none' && cs.visibility !== 'hidden' && parseFloat(cs.opacity) > 0.05;
  }
  function inFixedLayer(el) {
    for (var n = el; n && n !== document.body; n = n.parentElement) {
      if (getComputedStyle(n).position === 'fixed') return true;
    }
    return false;
  }
  function label(el) {
    return String(el.getAttribute('data-e2e') || el.getAttribute('role') || String(el.className).split(' ').pop() || el.tagName).slice(0, 48);
  }
  function tap(el) {
    var r = el.getBoundingClientRect();
    var o = { bubbles: true, cancelable: true, view: window, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 };
    try { el.dispatchEvent(new PointerEvent('pointerdown', o)); } catch (e) {}
    el.dispatchEvent(new MouseEvent('mousedown', o));
    try { el.dispatchEvent(new PointerEvent('pointerup', o)); } catch (e) {}
    el.dispatchEvent(new MouseEvent('mouseup', o));
    el.click();
  }
  function hide(el) { el.style.setProperty('display', 'none', 'important'); }
  function alpha(bg) { var m = /rgba?\(([^)]+)\)/.exec(bg || ''); if (!m) return 0; var p = m[1].split(','); return p.length > 3 ? parseFloat(p[3]) : 1; }
  function isMask(el) {
    var cs = getComputedStyle(el);
    if (cs.position !== 'fixed' || cs.pointerEvents === 'none' || !isVisible(el)) return false;
    var r = el.getBoundingClientRect();
    if (r.width < innerWidth * 0.9 || r.height < innerHeight * 0.6) return false;
    var a = alpha(cs.backgroundColor) * parseFloat(cs.opacity);   // rgba(0,0,0,.5) or #000 at opacity .5
    return a >= 0.15 && a <= 0.95 && !(el.innerText || '').trim() && !el.querySelector('video');
  }
  function findDismiss(root) {
    var cands = root.querySelectorAll('button,[role="button"],a,[aria-label],[data-e2e*="close"],[data-e2e*="cancel"],[data-e2e*="refuse"],svg');
    var byData = null;
    for (var i = 0; i < cands.length; i++) {
      var c = cands[i];
      if (!isVisible(c)) continue;
      var t = (c.innerText || c.getAttribute('aria-label') || '').trim();
      if (t && DISMISS_TEXT.test(t)) return c;
      if (!byData && /close|cancel|refuse/i.test(c.getAttribute('data-e2e') || '')) byData = c;
    }
    return byData;
  }
  function hideMasksNear(el) {
    var parent = el.parentElement;
    for (var hops = 0; parent && hops < 3; hops++, parent = parent.parentElement) {
      for (var i = 0; i < parent.children.length; i++) {
        var sib = parent.children[i];
        if (sib !== el && isMask(sib)) { hide(sib); log('hid mask ' + label(sib)); }
      }
    }
  }
  function scanNags() {
    var now = Date.now();
    var nodes = document.querySelectorAll(DIALOG_SEL);
    for (var i = 0; i < nodes.length; i++) {
      var d = nodes[i];
      if (!isVisible(d) || !inFixedLayer(d)) continue;
      var r = d.getBoundingClientRect();
      if (r.width * r.height < innerWidth * innerHeight * 0.12) continue;      // skip small UI (header pill)
      if (d.querySelector('input[type="text"],input[type="password"],input[type="email"],input[type="tel"],input:not([type])')) continue; // login form
      var text = (d.innerText || '').slice(0, 400);
      if (!NAG_TEXT.test(text)) continue;
      var first = handled.get(d);
      if (!first) {
        handled.set(d, now);
        var btn = findDismiss(d) || (d.parentElement && findDismiss(d.parentElement));
        if (btn) { tap(btn); log('tapped "' + (btn.innerText || btn.getAttribute('aria-label') || label(btn)).trim().slice(0, 24) + '" in ' + label(d) + ': ' + text.replace(/\s+/g, ' ').slice(0, 60)); }
        else { hide(d); hideMasksNear(d); log('hid ' + label(d) + ': ' + text.replace(/\s+/g, ' ').slice(0, 60)); }
      } else if (now - first > 900) {
        hide(d); hideMasksNear(d); log('still visible after tap, hid ' + label(d));
      }
    }
    // Standalone "continue on web"/"not now" controls in fixed layers (popups built from
    // separately positioned pieces, e.g. TikTok's launch popup).
    var leaves = document.querySelectorAll('button,[role="button"],a,div,span');
    for (var q = 0; q < leaves.length; q++) {
      var c = leaves[q];
      var t = (c.innerText || '').trim();
      if (!t || t.length > 30 || !WEB_CHOICE.test(t) || handled.get(c)) continue;
      if (c.firstElementChild && (c.firstElementChild.innerText || '').trim() === t) continue; // use innermost
      if (!isVisible(c) || !inFixedLayer(c)) continue;
      handled.set(c, now);
      tap(c);
      log('tapped standalone "' + t + '" (' + label(c) + ')');
    }

    // Lone dim masks with nothing on top (dialog content already gone/hidden).
    var all = document.querySelectorAll('body div');
    for (var j = 0; j < all.length; j++) {
      var m = all[j];
      if (!isMask(m)) continue;
      var p = m.parentElement, busy = false;
      for (var k = 0; p && k < p.children.length; k++) {
        var s = p.children[k];
        if (s !== m && isVisible(s) && (s.innerText || '').trim() && !NAG_TEXT.test(s.innerText)) { busy = true; break; }
      }
      if (!busy) { hide(m); log('hid lone mask ' + label(m)); }
    }
  }

  // --- video identity -------------------------------------------------------
  var elementIndex = 0;
  var indexKey = '__tqIndex';

  function idFor(video) {
    var src = video.currentSrc || video.src || '';
    // blob: URLs are per-render; still unique per video within a session,
    // but fall back to stable DOM hooks when possible.
    if (src && src.indexOf('blob:') !== 0) return 'src:' + src;
    var host = video.closest('[data-e2e]');
    if (host) {
      var e2e = host.getAttribute('data-e2e') || '';
      var desc = host.querySelector('[data-e2e$="desc"], [data-e2e$="description"]');
      var text = desc ? desc.textContent.trim().slice(0, 80) : '';
      var author = host.querySelector('[data-e2e$="author-uniqueid"], [data-e2e$="author"]');
      var who = author ? author.textContent.trim() : '';
      if (text || who) return 'e2e:' + e2e + ':' + who + ':' + text;
    }
    if (src) return 'blob:' + src;
    if (!video[indexKey]) video[indexKey] = ++elementIndex;
    return 'idx:' + video[indexKey];
  }

  // --- visibility tracking --------------------------------------------------
  var seen = new Set();
  var pendingId = null;
  var debounceTimer = null;

  function reportVisible(video) {
    var id = idFor(video);
    if (seen.has(id)) return;
    pendingId = id;
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(function () {
      if (pendingId && !seen.has(pendingId)) {
        seen.add(pendingId);
        if (seen.size > 2000) seen.clear(); // bound memory on long sessions
        post({ type: 'video', id: pendingId });
      }
      pendingId = null;
    }, DEBOUNCE_MS);
  }

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (en) {
      if (en.isIntersecting && en.intersectionRatio >= THRESHOLD) reportVisible(en.target);
    });
  }, { threshold: [THRESHOLD] });

  var tracked = new WeakSet();
  function track(video) {
    if (tracked.has(video)) return;
    tracked.add(video);
    io.observe(video);
  }
  function scan(root) {
    if (!root || !root.querySelectorAll) return;
    if (root.tagName === 'VIDEO') track(root);
    root.querySelectorAll('video').forEach(track);
  }

  var nagTimer = null;
  var mo = new MutationObserver(function (muts) {
    for (var i = 0; i < muts.length; i++) {
      var added = muts[i].addedNodes;
      for (var j = 0; j < added.length; j++) scan(added[j]);
    }
    clearTimeout(nagTimer);
    nagTimer = setTimeout(function () { dismissNags(); scanNags(); applyDesktopMode(); watchColumn(); escapeBrowseDialog(); }, 150);
  });

  function start() {
    installHideCSS();
    dismissNags();
    scanNags();
    applyDesktopMode();
    setInterval(function () { scanNags(); applyDesktopMode(); watchColumn(); escapeBrowseDialog(); }, 1000);   // sheets can animate in without DOM mutations
    scan(document.body);
    mo.observe(document.body, { childList: true, subtree: true });
    log('feed-observer installed');
  }

  // --- swipe → next/prev on layouts that page with buttons (desktop site) ----
  // If a vertical swipe didn't move the feed natively, press the site's own nav button.
  function inScrollable(el) {
    for (var n = el; n && n !== document.body; n = n.parentElement) {
      if (/^(INPUT|TEXTAREA|SELECT)$/.test(n.tagName) || n.isContentEditable) return true;
      var cs = getComputedStyle(n);
      if (/(auto|scroll)/.test(cs.overflowY) && n.scrollHeight > n.clientHeight + 4 && !n.querySelector('video')) return true;
    }
    return false;
  }
  // Comments live in their own panel (desktop: a column or drawer). Any visible one disables the shim.
  var COMMENT_SEL = '[data-e2e*="comment-list"],[data-e2e*="comment-panel"],[class*="CommentList"],[class*="CommentContainer"],[class*="DivCommentMain"]';
  function commentsOpen() {
    var els = document.querySelectorAll(COMMENT_SEL);
    for (var i = 0; i < els.length; i++) if (isVisible(els[i])) return true;
    return false;
  }
  // Only swipes that start on the video item count; never inside comments or scrollable panels.
  function shimTarget(t) {
    if (!t || !t.closest) return false;
    if (!t.closest('[data-e2e="recommend-list-item-container"],[data-e2e="feed-video"]')) return false;
    if (t.closest('[data-e2e*="comment"],[class*="Comment"],[class*="comment"]')) return false;
    return !inScrollable(t) && !commentsOpen();
  }
  var touch0 = null;
  document.addEventListener('touchstart', function (e) {
    if (e.touches.length !== 1 || !shimTarget(e.target)) { touch0 = null; return; }
    var v = mostVisibleVideo();
    touch0 = { x: e.touches[0].clientX, y: e.touches[0].clientY, t: Date.now(), v: v, top: v ? v.getBoundingClientRect().top : 0 };
  }, { passive: true, capture: true });
  document.addEventListener('touchend', function (e) {
    var s = touch0; touch0 = null;
    if (!s || !e.changedTouches.length) return;
    var dx = e.changedTouches[0].clientX - s.x, dy = e.changedTouches[0].clientY - s.y;
    if (Math.abs(dy) < 50 || Math.abs(dy) < Math.abs(dx) * 1.5 || Date.now() - s.t > 900) return;
    if (commentsOpen()) return;
    var btn = document.querySelector(dy < 0 ? '[data-e2e="feed-navigation-next"]' : '[data-e2e="feed-navigation-prev"]');
    if (!btn) return;
    setTimeout(function () {
      var v = mostVisibleVideo();
      var moved = v !== s.v || (v && Math.abs(v.getBoundingClientRect().top - s.top) > 40);
      if (!moved) { btn.click(); log('swipe → ' + (dy < 0 ? 'next' : 'prev') + ' button'); }
    }, 350);
  }, { passive: true, capture: true });

  // --- control API called from Swift ---------------------------------------
  function mostVisibleVideo() {
    var best = null, bestArea = 0;
    var vh = window.innerHeight, vw = window.innerWidth;
    document.querySelectorAll('video').forEach(function (v) {
      var r = v.getBoundingClientRect();
      var w = Math.max(0, Math.min(r.right, vw) - Math.max(r.left, 0));
      var h = Math.max(0, Math.min(r.bottom, vh) - Math.max(r.top, 0));
      var a = w * h;
      if (a > bestArea) { bestArea = a; best = v; }
    });
    return best;
  }

  // Nearest ancestor of el that actually scrolls vertically, else null (= window scrolls).
  function scrollContainer(el) {
    var node = el && el.parentElement;
    while (node && node !== document.body && node !== document.documentElement) {
      var cs = getComputedStyle(node);
      if (/(auto|scroll)/.test(cs.overflowY) && node.scrollHeight > node.clientHeight + 4) return node;
      node = node.parentElement;
    }
    return null;
  }

  window.__tq = {
    pause: function () {
      document.querySelectorAll('video').forEach(function (v) { try { v.pause(); } catch (e) {} });
    },
    resume: function () {
      var v = mostVisibleVideo() || document.querySelector('video');
      if (v) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
    },
    // Advance feed by one page (one video on the swipe feed). Best effort: honours
    // scroll-snap containers; falls back to window scroll. Returns what it scrolled.
    next: function () {
      var btn = document.querySelector('[data-e2e="feed-navigation-next"]');
      if (btn) { btn.click(); return 'button'; }
      var v = mostVisibleVideo();
      var c = scrollContainer(v);
      var h = c ? c.clientHeight : window.innerHeight;
      if (c) { c.scrollBy({ top: h, behavior: 'smooth' }); return 'container'; }
      window.scrollBy({ top: h, behavior: 'smooth' });
      return 'window';
    },
    // Debug: log every layer under the screen centre and what the page thinks it is.
    inspect: function () {
      var x = innerWidth / 2, y = innerHeight / 2;
      log('ua ' + navigator.userAgent.slice(0, 100) + ' | ' + navigator.platform + ' | ' + innerWidth + 'x' + innerHeight +
          ' vv ' + (window.visualViewport ? Math.round(visualViewport.width) + 'x' + Math.round(visualViewport.height) + '@' + visualViewport.scale.toFixed(2) : '-') + ' dpr ' + devicePixelRatio);
      ['anchoring-player-column', 'recommend-list-item-container', 'feed-video', 'anchoring-engagement-vertical', 'anchoring-description-layer'].forEach(function (k) {
        var e = document.querySelector('[data-e2e="' + k + '"]'); if (!e) return log('geo ' + k + ' missing');
        var r = e.getBoundingClientRect();
        log('geo ' + k + ' ' + Math.round(r.left) + '..' + Math.round(r.right) + ' x ' + Math.round(r.top) + '..' + Math.round(r.bottom));
      });
      var vv = document.querySelector('[data-e2e="feed-video"] video');
      if (vv) log('geo video ' + vv.videoWidth + 'x' + vv.videoHeight + ' fit=' + getComputedStyle(vv).objectFit);
      var els = document.elementsFromPoint(x, y).slice(0, 10);
      els.forEach(function (e, i) {
        var cs = getComputedStyle(e);
        log('L' + i + ' ' + e.tagName + ' ' + label(e) + ' pos=' + cs.position + ' bg=' + cs.backgroundColor +
            ' op=' + cs.opacity + ' pe=' + cs.pointerEvents + ' z=' + cs.zIndex + ' txt=' + (e.innerText || '').replace(/\s+/g, ' ').slice(0, 30));
      });
      return els.length;
    },
    // Previous video (mirror of next).
    prev: function () {
      var btn = document.querySelector('[data-e2e="feed-navigation-prev"]');
      if (btn) { btn.click(); return 'button'; }
      var v = mostVisibleVideo();
      var c = scrollContainer(v);
      var h = c ? c.clientHeight : window.innerHeight;
      if (c) { c.scrollBy({ top: -h, behavior: 'smooth' }); return 'container'; }
      window.scrollBy({ top: -h, behavior: 'smooth' });
      return 'window';
    },
    seenCount: function () { return seen.size; },
    resetSeen: function () { seen.clear(); }
  };

  if (document.body) start();
  else document.addEventListener('DOMContentLoaded', start);
})();
