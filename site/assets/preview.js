// The landing page's app screens: the slides move on by themselves until the
// visitor swipes, scrolls or uses the keys (never with reduced motion), and
// a click or tap brings the next one, so a mouse that cannot swipe still can.
(function () {
  var track = document.querySelector('.preview .slides');
  if (!track) return;
  var count = track.children.length;
  var timer = null;

  function next() {
    var index = Math.round(track.scrollLeft / track.clientWidth);
    track.scrollTo({ left: ((index + 1) % count) * track.clientWidth });
  }

  function stop() {
    if (timer) clearInterval(timer);
    timer = null;
  }

  ['touchstart', 'wheel', 'keydown'].forEach(function (type) {
    track.addEventListener(type, stop, { passive: true });
  });
  track.addEventListener('click', function () {
    stop();
    next();
  });

  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    timer = setInterval(next, 4000);
  }
})();
