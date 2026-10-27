# Issue 397: is_helper_pane -- is this pane one that enforces the helper models (a Builder pane, a plan-author pane,
# a fix round in the Builder's pane)? Builtins only. A seat pane's COMMANDECK_SEAT names its role (seat.sh exports it
# before the agent) and is checked before the worktree's COMMANDECK_BUILDER, so a plan-judge or reviewer seat inside
# a Builder worktree is not one. With no seat marker, COMMANDECK_BUILDER=1 is a Builder pane opened by hand.
is_helper_pane() {
  case "${COMMANDECK_SEAT:-}" in
    builder|plan-author*) return 0 ;;
    "") [ "${COMMANDECK_BUILDER:-}" = 1 ] ;;
    *) return 1 ;;
  esac
}
