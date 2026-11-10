// Counts visits to the intro site in Google Analytics, the same property
// the web app and the phone apps count in. Only the live site is counted,
// and nothing is handed to advertising. The claim page never loads this:
// its address carries a card's ticket.
(function () {
  if (location.hostname !== "soolgyul.com" && location.hostname !== "www.soolgyul.com") return;
  var id = "G-Z1MYHDWXHJ";
  var script = document.createElement("script");
  script.async = true;
  script.src = "https://www.googletagmanager.com/gtag/js?id=" + id;
  document.head.appendChild(script);
  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  gtag("set", {
    allow_google_signals: false,
    allow_ad_personalization_signals: false
  });
  gtag("js", new Date());
  gtag("config", id);
})();
