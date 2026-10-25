#!/usr/bin/env bash
# timeout: 120
# Issue 342: a Builder that has stopped never reads its inbox, so a message sent to it sat unread until someone typed into
# the pane by hand (and the duplicate-agent guard blocks that while the pane is busy). What this pins: a Builder pane that
# is idle or done, with an unread message addressed to it, is typed one INBOX line pointing it at its inbox; once per
# message, so a second tick types nothing and a new message types again; a read message, a message for someone else and a
# Builder that is mid-turn (it reads at its next check) are not typed into; and a failed inbox read types nothing.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
mkdir -p "$REPO/hooks/lib"; cp "$SOURCE/scripts/decision.sh" "$REPO/scripts/"; cp "$SOURCE/hooks/lib/project.sh" "$REPO/hooks/lib/"
tick 5000
wakes() { cat "$T/typed" 2>/dev/null | grep -c -- "--terminal $1 --text Signal INBOX" || true; }
msg() { # <handle> <id> <read 0|1> [to] -- one message in the pane's inbox
  jq -nc --arg h "${4:-$1}" --arg id "$2" --argjson r "$3" '{id: $id, to_handle: $h, from_handle: "term_main", type: "message", subject: "answer", read: $r, created_at: "1999-01-01T00:00:00Z"}' >> "$F/inbox-$1.jsonl"
  jq -sc '{ok: true, result: {messages: .}}' "$F/inbox-$1.jsonl" > "$F/inbox-$1"; }

bseat wt-i1 term_wt-i1 task_wt-i1 9000; state term_wt-i1 working; tick 10000
msg term_wt-i1 m1 0
tick 10030
[ "$(wakes term_wt-i1)" = 0 ] || fail "a Builder mid-turn was typed an INBOX line: it reads its inbox at its next check"
state term_wt-i1 idle; tick 10060
[ "$(wakes term_wt-i1)" = 1 ] || fail "an idle Builder with an unread message was not woken once: $(cat "$T/typed" 2>/dev/null)"
tick 10120
[ "$(wakes term_wt-i1)" = 1 ] || fail "the same unread message woke the Builder a second time"
msg term_wt-i1 m2 0; tick 10180
[ "$(wakes term_wt-i1)" = 2 ] || fail "a new message did not wake the Builder again"
# Two messages that arrive together are one line, not two.
msg term_wt-i1 m3 0; msg term_wt-i1 m4 0; tick 10240
[ "$(wakes term_wt-i1)" = 3 ] || fail "two new messages did not wake the Builder exactly once more: $(wakes term_wt-i1)"

# Read, or addressed to another handle: nothing to wake for.
bseat wt-i2 term_wt-i2 task_wt-i2 9000; state term_wt-i2 working; tick 11000
msg term_wt-i2 r1 1; msg term_wt-i2 o1 0 term_other; state term_wt-i2 "done"; tick 11060
[ "$(wakes term_wt-i2)" = 0 ] || fail "a read message, or one for another handle, woke the Builder"

# A done pane wakes too; a failed inbox read types nothing.
bseat wt-i3 term_wt-i3 task_wt-i3 9000; state term_wt-i3 working; tick 12000
msg term_wt-i3 d1 0; state term_wt-i3 "done"; tick 12060
[ "$(wakes term_wt-i3)" = 1 ] || fail "a done Builder with an unread message was not woken"
bseat wt-i4 term_wt-i4 task_wt-i4 9000; state term_wt-i4 working; tick 13000
echo 'not json' > "$F/inbox-term_wt-i4"; state term_wt-i4 idle; tick 13060
[ "$(wakes term_wt-i4)" = 0 ] || fail "an inbox read that failed woke the Builder"

# A wake Orca did not take (the send fails, or answers accepted:false: a paired phone can hold the pane's keyboard) is
# not a wake: nothing else wakes a stopped Builder, so the message stays owed and the next tick types it.
mv "$T/bin/orca-ide" "$T/bin/orca-real"
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "terminal send" ] && [ -e "$F/refuse" ]; then
  case \$(cat "$F/refuse") in fail) exit 1 ;; *) echo '{"ok":true,"result":{"accepted":false}}'; exit 0 ;; esac
fi
exec "$T/bin/orca-real" "\$@"
EOF
chmod +x "$T/bin/orca-ide"
n=5
for how in fail unaccepted; do
  n=$((n + 1)); bseat wt-i$n term_wt-i$n task_wt-i$n 9000; state term_wt-i$n working; tick $((n * 1000 + 8000))
  msg term_wt-i$n x$n 0; state term_wt-i$n idle; echo "$how" > "$F/refuse"; tick $((n * 1000 + 8060))
  [ "$(wakes term_wt-i$n)" = 0 ] || fail "the refused ($how) wake was typed"
  rm "$F/refuse"; tick $((n * 1000 + 8120))
  [ "$(wakes term_wt-i$n)" = 1 ] || fail "a wake Orca refused ($how) was not typed again on the next tick: $(wakes term_wt-i$n)"
  tick $((n * 1000 + 8180))
  [ "$(wakes term_wt-i$n)" = 1 ] || fail "after the accepted wake ($how), the same message woke the Builder again"
done
echo "PASS main-watch-inbox-wake.test.sh"
