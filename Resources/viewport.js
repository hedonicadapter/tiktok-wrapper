// viewport.js: injected at document start in desktop mode only.
// TikTok's desktop page says width=device-width (393 on the phone), but its layout needs ~490
// CSS px, so the right-hand buttons fall off-screen. Pin the layout width instead; WebKit then
// scales the page to fit the screen. The width placeholder below is replaced by Swift.
(function () {
  var CONTENT = 'width=__LAYOUT_WIDTH__, user-scalable=no, viewport-fit=cover';
  function ensure() {
    var head = document.head || document.documentElement;
    if (!head) return;
    var metas = document.querySelectorAll('meta[name="viewport"]');
    if (!metas.length) {
      var m = document.createElement('meta');
      m.setAttribute('name', 'viewport');
      head.insertBefore(m, head.firstChild);
      metas = [m];
    }
    for (var i = 0; i < metas.length; i++) {
      if (metas[i].getAttribute('content') !== CONTENT) metas[i].setAttribute('content', CONTENT);
    }
  }
  ensure();
  // TikTok may add or rewrite the meta while its app boots; keep it pinned.
  var mo = new MutationObserver(ensure);
  mo.observe(document.documentElement || document, { childList: true, subtree: true, attributes: true, attributeFilter: ['content'] });
  // After boot, only watch <head> to keep the cost near zero on the busy feed DOM.
  window.addEventListener('load', function () {
    setTimeout(function () {
      mo.disconnect();
      ensure();
      if (document.head) mo.observe(document.head, { childList: true, subtree: true, attributes: true, attributeFilter: ['content'] });
    }, 5000);
  });
})();
