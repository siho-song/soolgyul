// The landing page's app screens: the slides move on by themselves every
// four seconds. A swipe, a scroll or a key starts the wait again, and a
// click or tap brings the next one, so a mouse that cannot swipe still can.
// With reduced motion the slide changes without sliding (landing.css).
(function () {
  var track = document.querySelector('.preview .slides');
  if (!track) return;
  var count = track.children.length;
  var timer = null;

  function next() {
    var index = Math.round(track.scrollLeft / track.clientWidth);
    track.scrollTo({ left: ((index + 1) % count) * track.clientWidth });
  }

  function wait() {
    clearInterval(timer);
    timer = setInterval(next, 4000);
  }

  ['touchstart', 'wheel', 'keydown'].forEach(function (type) {
    track.addEventListener(type, wait, { passive: true });
  });
  track.addEventListener('click', function () {
    next();
    wait();
  });

  wait();
})();
