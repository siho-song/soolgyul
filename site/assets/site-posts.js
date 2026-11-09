// Fills the notice or FAQ page from the site_posts table the admin console
// writes: notices newest first, FAQ answers in their order. The Supabase
// address and its publishable key come from /site-config.js, which
// tools/deploy_web.sh writes from config/env/production.env.
(function () {
  var list = document.querySelector('[data-site-posts]');
  var status = document.querySelector('[data-site-posts-status]');
  if (!list || !status) return;
  var kind = list.getAttribute('data-site-posts');
  var config = window.SOOLGYUL_SUPABASE;
  var say = function (text) { status.textContent = text; status.hidden = false; };
  var failed = function () { say('불러오지 못했어요. 잠시 후 다시 열어 주세요.'); };
  if (!config) { failed(); return; }

  var order = kind === 'faq' ? 'sort_order.asc,published_at.asc' : 'published_at.desc';
  var url = config.url + '/rest/v1/site_posts?select=title,body,published_at'
    + '&kind=eq.' + kind + '&status=eq.published&order=' + order;
  var day = new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul', year: 'numeric', month: 'long', day: 'numeric'
  });
  var add = function (tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    node.textContent = text;
    list.appendChild(node);
  };

  fetch(url, { headers: { apikey: config.key } })
    .then(function (response) {
      if (!response.ok) throw new Error(String(response.status));
      return response.json();
    })
    .then(function (rows) {
      if (rows.length === 0) { say(list.getAttribute('data-empty')); return; }
      status.hidden = true;
      rows.forEach(function (row) {
        add('h2', '', row.title);
        if (kind === 'notice' && row.published_at) {
          add('p', 'updated', day.format(new Date(row.published_at)));
        }
        if (row.body) add('p', 'post-body', row.body);
      });
    })
    .catch(failed);
})();
