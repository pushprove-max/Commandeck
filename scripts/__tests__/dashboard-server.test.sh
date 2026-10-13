#!/usr/bin/env bash
# The dashboard's page server accepts one write. These cases hold the boundary: only a checked panel
# layout reaches disk, only as layout.js, and every other request changes nothing.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRV=$HERE/../dashboard_serve.py
T=$(mktemp -d)
PID=''
trap '[ -z "$PID" ] || kill "$PID" 2>/dev/null; rm -rf "$T"' EXIT
pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$SRV" ] || fail "no page server at $SRV"
mkdir -p "$T/out" && echo page > "$T/out/index.html" && echo secret > "$T/outside"
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 "$SRV" "$PORT" 127.0.0.1 "$T/out" & PID=$!
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/index.html" && break; sleep 0.1; done
U=http://127.0.0.1:$PORT
# put <want-status> <case> <path> <body> [content-type]
put() {
  local got
  got=$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: ${5:-application/json}" --data-binary "$4" "$U$3")
  [ "$got" = "$1" ] || fail "$2: PUT $3 answered $got, want $1"
  pass=$((pass + 1))
}
same() { [ "$(cat "$T/out/layout.js" 2>/dev/null)" = "$1" ] || fail "$2: layout.js is $(cat "$T/out/layout.js" 2>/dev/null)"; pass=$((pass + 1)); }

[ "$(curl -s "$U/index.html")" = page ] || fail "serves_the_page: the page is still served"; pass=$((pass + 1))
# The host numbers each save: a save names the number of the layout it was made over (0 before any), and the
# host writes the next number. A layout file from before numbering, or none, is number 0.
echo 'window.DASH_LAYOUT = null;' > "$T/out/layout.js"
GOOD='{"rev":0,"order":["alerts","builds"],"sizes":{"host":3},"heights":{"relay":"half","host":333},"hidden":["issues"],"closed":["tooling-batch-2026-10-12e"],"collapsed":["merged-more"]}'
put 204 valid_layout_is_saved /layout "$GOOD"
WANT='window.DASH_LAYOUT = {"closed": ["tooling-batch-2026-10-12e"], "collapsed": ["merged-more"], "heights": {"host": 333, "relay": "half"}, "hidden": ["issues"], "order": ["alerts", "builds"], "rev": 1, "sizes": {"host": 3}};'
same "$WANT" valid_layout_is_saved
[ "$(curl -s "$U/layout.js")" = "$WANT" ] || fail "saved_layout_is_served: another browser reads what was saved"; pass=$((pass + 1))
# A browser's own guess at freshness kept an old app.js running after an update; every file is revalidated.
for f in index.html layout.js; do
  curl -s -D - -o /dev/null "$U/$f" | grep -qi '^cache-control: no-cache' || fail "files_are_revalidated: $f is served without Cache-Control: no-cache"; pass=$((pass + 1))
done
# A save made over an older layout than the host holds (the old page's, landing after the reload's replay)
# is refused and answered with the number held, so the page can send its layout again over that one.
refused() { [ "$(curl -s -w ' %{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary "$2" "$U/layout")" = '{"rev": 1} 409' ] || fail "$1: want 409 with the number held"; pass=$((pass + 1)); }
refused older_save_is_refused '{"rev":0,"hidden":["deploys"]}'
refused save_over_a_number_the_host_never_gave_is_refused '{"rev":7,"hidden":["deploys"]}'
# The host's own next number is the one a wrong check would take for "written": nothing was, so it is no 204.
refused save_over_the_next_number_is_refused '{"rev":2,"hidden":["deploys"]}'
same "$WANT" older_save_is_refused
put 400 save_with_no_number_refused /layout '{"hidden":["deploys"]}'
for bad in '"1"' -1 true 1.0 null 9007199254740992; do put 400 "number_${bad}_refused" /layout "{\"rev\":$bad}"; done

# Every refusal leaves the saved layout exactly as it was.
put 400 unknown_key_refused /layout '{"rev":1,"order":[],"script":"x"}'
put 400 width_out_of_range_refused /layout '{"rev":1,"sizes":{"host":9}}'
put 400 width_not_a_whole_number_refused /layout '{"rev":1,"sizes":{"host":true}}'
put 400 height_not_a_known_word_refused /layout '{"rev":1,"heights":{"host":"huge"}}'
# A panel height the owner dragged to is a whole number of pixels inside the page's own bounds; nothing else is a height.
for bad in 59 4001 333.5 true '"333"' '[333]' -333; do put 400 "custom_height_${bad}_refused" /layout "{\"rev\":1,\"heights\":{\"host\":$bad}}"; done
put 400 id_with_markup_refused /layout '{"rev":1,"hidden":["</script><script>alert(1)"]}'
put 400 id_not_text_refused /layout '{"rev":1,"order":[5]}'
put 400 not_an_object_refused /layout '["alerts"]'
put 400 not_json_refused /layout 'not json'
put 413 oversized_body_refused /layout "{\"rev\":1,\"order\":[\"$(head -c 20000 /dev/zero | tr '\0' a)\"]}"
put 403 other_path_refused /data.js "$GOOD"
put 403 path_outside_the_folder_refused '/../outside' "$GOOD"
put 403 nested_path_refused /layout/../index.html "$GOOD"
# A form post from another site's page cannot set a JSON content type without asking first.
put 403 plain_content_type_refused /layout "$GOOD" text/plain
GOOD=${GOOD/\"rev\":0/\"rev\":1}  # from here a write that got through would be over the layout held
for m in POST DELETE PATCH; do
  got=$(curl -s -o /dev/null -w '%{http_code}' -X "$m" -H 'Content-Type: application/json' --data-binary "$GOOD" "$U/layout")
  case $got in 4*|5*) pass=$((pass + 1)) ;; *) fail "only_put_writes: $m /layout answered $got" ;; esac
done
same "$WANT" refusals_change_nothing
[ "$(cat "$T/out/index.html")" = page ] && [ "$(cat "$T/outside")" = secret ] || fail "refusals_change_nothing: another file changed"
[ "$(find "$T" -type f | wc -l | tr -d ' ')" = 3 ] || fail "refusals_change_nothing: a stray file was written: $(find "$T" -type f)"
pass=$((pass + 2))
# Two saves at once shared one temporary file: one could publish the other's half-written text or fail. All eight
# are made over layout 1, so the host takes exactly one and refuses the rest.
BIG=$(head -c 11400 /dev/zero | tr '\0' a | fold -w 60 | paste -sd, - | sed 's/,/","/g')
codes=$(for i in $(seq 1 8); do curl -s --retry 5 --retry-connrefused -o /dev/null -w '%{http_code}\n' -X PUT -H 'Content-Type: application/json' --data-binary "{\"rev\":1,\"order\":[\"p$i\",\"$BIG\"]}" "$U/layout" & done; wait)
[ "$(sort <<<"$codes" | tr '\n' ' ')" = '204 409 409 409 409 409 409 409 ' ] || fail "overlapping_saves_each_land_whole: one save lands and seven are refused: $(sort <<<"$codes" | uniq -c | tr '\n' ' ')"
python3 -c 'import json, sys; s = open(sys.argv[1]).read(); assert s.startswith("window.DASH_LAYOUT = ") and s.endswith(";\n"); assert json.loads(s[20:-2])["rev"] == 2' "$T/out/layout.js" || fail "overlapping_saves_each_land_whole: the saved file is one whole layout"
[ "$(find "$T" -type f | wc -l | tr -d ' ')" = 3 ] || fail "overlapping_saves_each_land_whole: a temporary file was left behind: $(find "$T" -type f)"
pass=$((pass + 3))
# The write is the page's own: the same body from another site's page is refused like its reads.
got=$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' -H 'Origin: http://other.example' --data-binary "$GOOD" "$U/layout")
[ "$got" = 403 ] || fail "another_sites_page_refused: PUT /layout from another origin answered $got"; pass=$((pass + 1))
# A Reset layout is about panels: the builds cleared before it stay cleared.
put 204 reset_saves_an_empty_layout /layout '{"rev":2}'
same 'window.DASH_LAYOUT = {"closed": ["tooling-batch-2026-10-12e"], "rev": 3};' reset_saves_an_empty_layout
# The cases below are about projects' slots: they start from a file that holds the number alone.
echo 'window.DASH_LAYOUT = {"rev": 3};' > "$T/out/layout.js"
# One file, a layout per project: a save that names a project lands in that project's slot and nowhere else. The
# home project's layout stays at the top, as it was before projects, and the file keeps one number for all of them.
put 204 project_layout_is_saved /layout '{"rev":3,"project":"beta","hidden":["host"]}'
same 'window.DASH_LAYOUT = {"projects": {"beta": {"hidden": ["host"]}}, "rev": 4};' project_layout_is_saved
put 204 home_save_keeps_every_project /layout '{"rev":4,"order":["alerts"]}'
put 204 second_project_has_its_own_slot /layout '{"rev":5,"project":"_gamma.2","sizes":{"host":2}}'
same 'window.DASH_LAYOUT = {"order": ["alerts"], "projects": {"_gamma.2": {"sizes": {"host": 2}}, "beta": {"hidden": ["host"]}}, "rev": 6};' projects_never_share_a_layout
refused() { [ "$(curl -s -w ' %{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary "$2" "$U/layout")" = '{"rev": 6} 409' ] || fail "$1: want 409 with the number held"; pass=$((pass + 1)); }
refused project_save_over_an_older_layout_is_refused '{"rev":5,"project":"beta","hidden":[]}'
# The name is a key in that one file and never a path; one that could not be a project's name is refused all the same.
for bad in '".."' '"."' '"/etc/passwd"' '"a/b"' '"a%2Fb"' '"..%2f..%2fdata"' '""' '"__proto__"' 5 null '["beta"]' "\"$(head -c 81 /dev/zero | tr '\0' a)\""; do
  put 400 "project_name_${bad:0:20}_refused" /layout "{\"rev\":6,\"project\":$bad,\"hidden\":[]}"
done
put 400 a_save_cannot_write_the_slots_itself /layout '{"rev":6,"projects":{"beta":{}}}'
put 403 project_in_the_path_refused '/layout?project=beta' '{"rev":6,"hidden":[]}'
put 403 project_as_a_folder_refused /p/beta/layout '{"rev":6,"hidden":[]}'
same 'window.DASH_LAYOUT = {"order": ["alerts"], "projects": {"_gamma.2": {"sizes": {"host": 2}}, "beta": {"hidden": ["host"]}}, "rev": 6};' refused_project_saves_change_nothing
[ "$(find "$T" -type f | wc -l | tr -d ' ')" = 3 ] || fail "refused_project_saves_change_nothing: a stray file was written: $(find "$T" -type f)"; pass=$((pass + 1))
# Made-up names cannot grow the file without end: it holds 200 projects and a new one is refused; a held one still saves.
python3 -c 'import json; print("window.DASH_LAYOUT = %s;" % json.dumps({"rev": 6, "projects": {"p%d" % i: {} for i in range(200)}}))' > "$T/out/layout.js"
put 400 a_201st_project_is_refused /layout '{"rev":6,"project":"one-more","hidden":[]}'
put 204 a_held_project_still_saves /layout '{"rev":6,"project":"p7","hidden":["host"]}'
# A slot on disk that no checked save could have written is not written back.
echo 'window.DASH_LAYOUT = {"rev": 2, "order": 5, "projects": {"beta": {"hidden": ["ok"]}, "bad/name": {}, "worse": {"script": "x"}}};' > "$T/out/layout.js"
put 204 unchecked_values_on_disk_are_dropped /layout '{"rev":2,"project":"new","hidden":[]}'
same 'window.DASH_LAYOUT = {"projects": {"beta": {"hidden": ["ok"]}, "new": {"hidden": []}}, "rev": 3};' unchecked_values_on_disk_are_dropped
# A cleared build stays cleared. A tab that never saw another tab's clear sends its own list again over the newer
# number (the 409 gives it the number and nothing else), and the host keeps both; a Reset layout, which sends no
# list, keeps them too. One project's cleared builds are never another's. 200 names are kept, the newest.
echo 'window.DASH_LAYOUT = null;' > "$T/out/layout.js"
put 204 first_tab_clears_one /layout '{"rev":0,"project":"alpha","closed":["unit-a"]}'
put 409 second_tab_is_behind /layout '{"rev":0,"project":"alpha","closed":["unit-b"]}'
put 204 second_tab_clears_another /layout '{"rev":1,"project":"alpha","closed":["unit-b"]}'
put 204 another_project_clears_its_own /layout '{"rev":2,"project":"beta","closed":["unit-z"]}'
put 204 reset_layout_sends_no_list /layout '{"rev":3,"project":"alpha"}'
same 'window.DASH_LAYOUT = {"projects": {"alpha": {"closed": ["unit-a", "unit-b"]}, "beta": {"closed": ["unit-z"]}}, "rev": 4};' cleared_builds_stay_cleared_per_project
# The host trusts its own order of first sight and nothing a tab sends: it adds the names it does not hold, never
# moves or drops one it holds because of an incoming list, and keeps 2000 a project, dropping its own oldest.
names() { python3 -c 'import json, sys; a, b = int(sys.argv[2]), int(sys.argv[3]); print(json.dumps({"rev": int(sys.argv[1]), "project": "alpha", "closed": ["%s%d" % (sys.argv[4], i) for i in range(a, b)]}))' "$@"; }
alpha() { sed -e 's/^window\.DASH_LAYOUT = //' -e 's/;$//' "$T/out/layout.js" | jq -c ".projects.alpha.closed | $1"; }
put 204 a_hundred_and_fifty_cleared /layout "$(names 4 0 150 old)"
put 204 and_a_hundred_and_fifty_more /layout "$(names 5 0 150 new)"
[ "$(alpha '[length, .[0], .[2], .[-1]]')" = '[302,"unit-a","old0","new149"]' ] || fail "more_than_one_saves_worth_is_held: $(alpha '[length, .[0], .[2], .[-1]]')"; pass=$((pass + 1))
HELD=$(alpha .)
put 204 a_stale_tab_replays_old_names /layout "$(names 6 0 150 old)"
[ "$(alpha .)" = "$HELD" ] || fail "a_replay_of_held_names_changes_nothing: $(alpha '[length, .[0], .[-1]]')"; pass=$((pass + 1))
put 409 a_tab_behind_is_refused /layout "$(names 5 0 100 stale)"
put 204 and_its_retry_adds_its_names /layout "$(names 7 0 100 stale)"
[ "$(alpha '[length, .[0], .[301], .[-1]]')" = '[402,"unit-a","new149","stale99"]' ] || fail "the_409_retry_evicts_nothing: $(alpha '[length, .[0], .[301], .[-1]]')"; pass=$((pass + 1))
HELD=$(alpha .)
put 204 a_save_that_names_no_cleared_build /layout '{"rev":8,"project":"alpha","hidden":["host"]}'
[ "$(alpha .)" = "$HELD" ] || fail "a_save_before_the_first_snapshot_changes_nothing: $(alpha length)"; pass=$((pass + 1))
[ "$(sed -e 's/^window\.DASH_LAYOUT = //' -e 's/;$//' "$T/out/layout.js" | jq -c '.projects.beta.closed')" = '["unit-z"]' ] || fail "another_projects_cleared_builds_are_as_they_were"; pass=$((pass + 1))
# 2000 held: the next new name drops the host's own oldest, and a replay of the newest 200 drops nothing.
python3 -c 'import json; print("window.DASH_LAYOUT = %s;" % json.dumps({"rev": 9, "projects": {"alpha": {"closed": ["c%d" % i for i in range(2000)]}}}))' > "$T/out/layout.js"
put 204 one_more_than_the_host_keeps /layout '{"rev":9,"project":"alpha","closed":["newest"]}'
[ "$(alpha '[length, .[0], .[-1]]')" = '[2000,"c1","newest"]' ] || fail "the_hosts_own_oldest_is_dropped: $(alpha '[length, .[0], .[-1]]')"; pass=$((pass + 1))
put 204 a_replay_of_the_newest /layout "$(names 10 1800 2000 c)"
[ "$(alpha '[length, .[0], .[-1]]')" = '[2000,"c1","newest"]' ] || fail "a_replay_at_the_limit_drops_nothing: $(alpha '[length, .[0], .[-1]]')"; pass=$((pass + 1))
# A cleared build is named by its 40-character commit: 200 of them, with a layout beside them, fit one save.
echo 'window.DASH_LAYOUT = null;' > "$T/out/layout.js"
put 204 the_largest_cleared_list_fits_one_save /layout "$(python3 -c 'import json; print(json.dumps({"rev": 0, "project": "alpha", "order": ["p%d" % i for i in range(20)], "hidden": ["p%d" % i for i in range(20)], "collapsed": ["p%d" % i for i in range(20)], "sizes": {"p%d" % i: 2 for i in range(20)}, "heights": {"p%d" % i: "half" for i in range(20)}, "closed": ["%040x" % i for i in range(200)]}))')"
echo "PASS: dashboard-server ($pass checks)"
