# Numbers

`scripts/proof-run.sh` builds a throwaway fixture machine in a temporary
folder: an isolated home with existing settings, a small Node project, and
stubs for Orca, Claude, Codex and the service manager. It runs setup, a scripted
unit and uninstall for each profile. No real model or service is started.

It reports startup bytes, scripted hook counts and timings, clear-line checks
and restoration of fixture files. These are fixture measurements, not a
promise of production speed. Tokens, cache behavior, real review convergence
and restart takeover need a live build; the script labels those not measured.
Run it from a clone when you want current figures:

```bash
bash scripts/proof-run.sh
bash scripts/proof-run.sh --profile claude
```
