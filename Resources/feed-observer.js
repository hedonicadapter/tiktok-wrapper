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
    nagTimer = setTimeout(dismissNags, 150);
  });

  function start() {
    installHideCSS();
    dismissNags();
    scan(document.body);
    mo.observe(document.body, { childList: true, subtree: true });
    log('feed-observer installed');
  }

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
      var v = mostVisibleVideo();
      var c = scrollContainer(v);
      var h = c ? c.clientHeight : window.innerHeight;
      if (c) { c.scrollBy({ top: h, behavior: 'smooth' }); return 'container'; }
      window.scrollBy({ top: h, behavior: 'smooth' });
      return 'window';
    },
    seenCount: function () { return seen.size; },
    resetSeen: function () { seen.clear(); }
  };

  if (document.body) start();
  else document.addEventListener('DOMContentLoaded', start);
})();
