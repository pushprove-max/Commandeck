# The decisions-ledger id of one AskUserQuestion question: its header slug
# plus the day it was asked. ask-records-decision.sh adds the row under this id
# and ruling-log.sh answers it, so both derive it here and nowhere else.
def decision_id($day):
  ((.header // "") | ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; ""))
  | (if . == "" then "ask" else . end) + "-" + $day;
