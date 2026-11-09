#!/bin/sh
# Writes the per-environment values Info.plist reads ($(KAKAO_NATIVE_APP_SCHEME)
# and the Google IDs) from the dart-defines of the env file the build was
# started with (--dart-define-from-file). Runs as a Runner scheme pre-action,
# before the build settings are read.
out="$SRCROOT/Flutter/DartDefines.xcconfig"
: > "$out"
for define in $(echo "$DART_DEFINES" | tr ',' ' '); do
  pair=$(echo "$define" | base64 --decode)
  case "$pair" in
    KAKAO_NATIVE_APP_SCHEME=*|GOOGLE_IOS_URL_SCHEME=*|GOOGLE_IOS_CLIENT_ID=*|GOOGLE_WEB_CLIENT_ID=*)
      echo "$pair" >> "$out" ;;
  esac
done
