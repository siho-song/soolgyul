// A page opened from the app hides its link to the site's home: there, the
// way back is the in-app browser's close button. The mark stays for the
// visit, so a page reached from this one hides it too.
(function () {
  var fromApp = new URLSearchParams(location.search).get("from") === "app";
  try {
    if (fromApp) sessionStorage.setItem("soolgyul-from-app", "1");
    fromApp = sessionStorage.getItem("soolgyul-from-app") === "1";
  } catch (_) {
    // Storage blocked: the query alone decides.
  }
  if (fromApp) document.documentElement.classList.add("from-app");
})();
