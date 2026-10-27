## The issues

1. #<n>: <title>
   Size: <the files it touches>; shared with <item numbers>, or independent; ~<n>K tokens to read
2. <an item with no issue: its title>
   Size: ...

A line that starts with `Closes:` and lists issues (`Closes: #12, #13`) closes them at the merge: the merge commit
carries each as `Closes #12`, and the merge closes the issue on GitHub. It closes only issues of the numbered list
above, as the launch read it (its dry run prints the list); leave the line out for an issue the unit only advances.

## The batch (done criteria)

One paragraph per item above, by its number: what is built, and what done
means. Then the tests to write first, and how the batch will be reviewed.
An item that adds a step to the build, merge, review or push flow carries a
`Catches:` line: what the step catches that no existing step does.
Optional: a line `Estimated size: ~<n> changed lines`. Under 150, a risky trigger gets
one plan judge, not two; with no line, or 150 or more, the plan tier stays Panel.

- Name every reader of anything an item deletes (exports, docs, scripts that
  call it), so none is left calling it.
- An input called "existing" cites the code that computes it and the code that
  fills it on the real path; a type, a schema field or an initial state is
  neither. With no such code, the item does not rely on it.
- Each item names its test file and case, and says which case fails before the
  change (red first) and which only pins behaviour that already holds. An item
  whose files are all docs or config may name none: say why, and the command
  that proves it.

## Launch

Required: builder-launch.sh refuses a batch without it, and a plan seat's
spec copies both lines. A new unit opens only on an order that names it.

Launch: new unit <unit> | add to <unit>
Order: <the owner's words, verbatim>

`add to <unit>` is not a launch: put the work in that unit's rulings file
and run `builder-add-work.sh <unit> --unless '<path>:<text>'`, one probe per item.

## Prior art

Required: builder-launch.sh refuses a batch without it. Which standard
governs this change, which library or managed service already does it (the
project's `.claude/paved-road.md`, by area), and why we build instead if we do.

## Data design

Required: builder-launch.sh refuses a batch without it. For each piece of state the
batch adds or changes (a file, a record, a counter, a lock, a log, a setting): where
it lives, who writes it, who reads it, when it resets, and what a retry runs. Write
`none: <why no state is added or changed>` when there is none.

- <piece of state>: lives in <where>; written by <who>; read by <who>; reset when <when>; a retry runs <what>; a half write leaves <what>, recovered by <how>; two concurrent writes <result>; retries owned by <code>, at most <n>

## What can go wrong

Required: builder-launch.sh refuses a batch with no such section in it or in its plan. The cases a reviewer and
every fix round check the build against, one named test per case: limits (empty, tiny, huge, cut off mid-way),
timing (two actions or replies in either order, retries, timeouts) and odd data (special characters, missing
fields, duplicates, old shapes).

- <case>: <the test that checks it>

## Plan

Required: builder-launch.sh refuses a batch without it. The plan the owner
read before saying go, by its path: `.claude/plans/<file>.md`, committed on
main. With no plan, main launches with
`--skip-plan --reason '<one line>'` instead.
