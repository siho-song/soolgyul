#!/usr/bin/env bash
# Deploys a web surface to Vercel: `site` is the intro site (soolgyul.com),
# `app` is the Flutter web build (app.soolgyul.com) and `admin` the editorial
# admin (admin.soolgyul.com). Add --prod to replace the live site; without it
# Vercel gives a private preview address.
set -euo pipefail
cd "$(dirname "$0")/.."

# Links a folder to its Vercel project. A folder without the link (a fresh
# checkout, a wiped build) would otherwise make the CLI create a new project
# instead of updating the one behind the domain.
link_project() {
  npx vercel link --yes --project "$2" --cwd "$1"
}

# Builds one Flutter web entry point into its own folder and links it.
build_flutter_web() {
  local target=$1 project=$2
  dir="build/$project"
  flutter build web --release -t "$target" -o "$PWD/$dir" \
    --dart-define-from-file=config/env/production.env
  link_project "$dir" "$project"
}

# The notice and FAQ pages read site_posts with the production Supabase
# address and publishable key, which reach the static site as site-config.js.
write_site_config() {
  local env=config/env/production.env url key
  url=$(grep '^SUPABASE_URL=' "$env" | cut -d= -f2-)
  key=$(grep '^SUPABASE_PUBLISHABLE_KEY=' "$env" | cut -d= -f2-)
  if [[ -z "$url" || -z "$key" ]]; then
    echo "$env needs SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY" >&2
    exit 1
  fi
  printf 'window.SOOLGYUL_SUPABASE = { url: "%s", key: "%s" };\n' \
    "$url" "$key" > site/site-config.js
}

case "${1:-}" in
  site)
    dir=site
    write_site_config
    link_project "$dir" soolgyul-web
    ;;
  app) build_flutter_web lib/main.dart soolgyul-app ;;
  admin) build_flutter_web lib/admin_main.dart soolgyul-admin ;;
  *)
    echo "usage: tools/deploy_web.sh site|app|admin [--prod]" >&2
    exit 1
    ;;
esac

npx vercel deploy "$dir" "${@:2}"
