# Credential rotation — 2026-07 audit follow-up

Status: **PENDING — requires operator action.** Nothing in this file asserts
that rotation has happened. Replace the "Pending" rows with real receipts
(who, when, where the new secret lives) once rotation is done; do not mark
anything rotated without doing it.

## Why

PR #58 removed live Backblaze B2 application keys that had shipped inside the
compiled iOS binary. Removal from HEAD does not revoke them: the keys remain
recoverable from git history and from any previously distributed build. An
untracked local release xcconfig was also observed carrying a Meta client
token annotated as previously committed.

## Required rotations

| Credential | Where it leaked | Action | Status |
|---|---|---|---|
| Backblaze B2 application key (upload) | Compiled into iOS binary until PR #58; still in git history | Revoke the key in the Backblaze console, issue a replacement, store it server-side only (never in client config) | Pending |
| Meta client token | Untracked release xcconfig on a dev machine, annotated as previously committed | Rotate in the Meta developer console; keep out of tracked files | Pending |

## Receipt format (fill in when done)

```
credential: <name>
revoked_at: <UTC timestamp>
rotated_by: <person>
new_secret_location: <secret manager path — never the value itself>
old_key_confirmed_disabled: <how it was verified>
```

## Standing rule

Client binaries must never embed provider secrets. Upload credentials are
minted server-side per session; anything that requires a static secret
belongs behind a Cloud Function.
