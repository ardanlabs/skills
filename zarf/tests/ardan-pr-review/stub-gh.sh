#!/bin/sh
# Fake `gh` for the suite's pull-request runs: answers exactly the calls intake makes for
# `--pr 1`, from FX_HEAD / FX_BASE (commits), FX_GH_PERM (the author's permission), and
# FX_GH_CROSS (true when the head branch is in a fork). Anything else fails loudly.
url=https://github.com/fx/fx/pull/1
case "$*" in
  "pr view 1 --json headRefOid,baseRefOid,url --jq "*) echo "$FX_HEAD $FX_BASE $url" ;;
  "pr view 1 --json headRefOid,baseRefOid,url") printf '{"headRefOid":"%s","baseRefOid":"%s","url":"%s"}\n' "$FX_HEAD" "$FX_BASE" "$url" ;;
  "pr view 1 --json title,body,url --jq "*) printf '# Fixture PR\n\n%s\n\nFixture body\n' "$url" ;;
  "pr view 1 --json title,body,url") printf '{"title":"Fixture PR","body":"Fixture body","url":"%s"}\n' "$url" ;;
  "pr view 1 --json author,isCrossRepository,url --jq "*) echo "maint $FX_GH_CROSS $url" ;;
  "api --hostname github.com repos/fx/fx/collaborators/maint/permission --jq .permission") echo "$FX_GH_PERM" ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 1 ;;
esac
