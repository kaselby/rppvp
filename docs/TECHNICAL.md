# HonorBound: technical notes

For contributors. Player docs are in the [README](../README.md).

## Discovery and compatibility (`whisper-all` branch)

This branch drops the hidden channel. Everyone you see (nameplates, mouseover,
target, focus, chat speakers) is asked directly by a hidden addon whisper,
same realm or not. Discovery uses GUIDs, because Forever's surname-bearing
character names can differ between chat and unit frames. Forever names are
"First Surname": whispers must go to `First-Surname`, the form `UnitName`
returns (surname in the realm slot). `First Surname-Realm`, which
`GetPlayerInfoByGUID` and incoming whisper senders give, bounces, so every
whisper address is normalized to the first form.

Whispers don't cross factions, so opposite-faction players are never asked,
and a remembered (saved) status only stands in for players of your own faction,
since nobody else can be re-checked. Custom unit-frame and nameplate
replacements (such as Plater) aren't supported, and Blizzard blocks addons from
changing nameplates inside dungeons. The oath is voluntary and enforced on your
own client, not verified by the server; only the flag check comes from the
server.

### What gets sent

| Message | Route | Sent when |
|---|---|---|
| `S\|2\|…` + `P\|1\|…` status and pledge level | Group, guild | Login, every 60 s, on oath/flag/group change |
| `WQ\|1\|…` probe, carries your status | Whisper | Anyone of your faction you see: remembered addon users first, then mouseover/target, chat, nameplates. Skipped if known (re-checked before the 5 min expiry), awaiting a reply, or on the no-addon list |
| `WR\|1\|…` reply, carries your status | Whisper | A `WQ` arrives. At most one per player per minute |

No reply within 30 s puts a player on the no-addon list for 2 hours (saved).
Any message from them clears it.

### Rate limits

The client's per-prefix allowance (10 messages, refilling 1 a second) doesn't
apply to whispers outside instanced content (Warcraft Wiki,
`C_ChatInfo.SendAddonMessage`), so outside dungeons and raids every waiting
reply and probe goes out each second, unpaced. Inside, and for group/guild
status, the old budget applies (burst 5, then one every 2 s). The same page
warns of an undocumented **server-side** throttle and possible disconnects if
too much is sent at once, which is what this branch is for testing.

- Any refused send (the result code, e.g. "sending too fast, the game is
  throttling us") and the server's own throttle notice are reported in debug
  mode (`/honor debug on`): the first at once, then one summary every 10 s.
  Players never see them, nor raw Lua errors (also debug only).
- `/honor rate N` caps whispers at N a second for testing; `/honor rate off`
  removes the cap.
- `/honor why` (target or hover a player): every condition behind their
  nameplate crest — known, sworn, faction, flag, nameplate frame visible,
  crest showing, nameplate addons loaded.

Debug: `/honor debug on` shows status updates, failures and a summary line
each minute; `/honor debug verbose` adds every whisper probe and reply. While
debugging, players without a real crest show a **light grey** crest while
they're being asked and a **dark grey** one once marked no-addon (nameplates,
unit frames and chat), and each summary includes a coverage line over the
nameplates in view. First chat lines gain their crest when the probe answers
(`TransformMessages`).

### Simulation

Few players run the addon yet, so almost every probe ends in the 30 s no-reply
timeout. `/honor sim N` makes N% of the players you ask answer like addon
users, 0.5-3 s after the real probe goes out, and wear a full crest on
nameplates, unit frames, tooltips and chat (whatever their PvP flag).
Everything else stays real: probes, pacing, queue order, timeouts and the
saved no-addon list. It turns debug on and prints the
coverage line every 15 s, so you can watch a crowd fill in at real speed.

- Who answers is a fixed hash of the player's GUID, not a random roll: every
  tester with the same N sees the same simulated users, with nothing to sync.
- Simulated users are never saved, and the no-addon list can't hide them.
- `/honor sim off` removes simulated crests and keeps everything learned for
  real. `/honor sim` prints the coverage line.

## Pledge verification (`Verify.lua`)

Was HonorBound running for all the play since the pledge? `/played` is
counted by the server and keeps going while the addon is off, so disabling
it, unflagging, reflagging and re-enabling still leaves a gap.

- Record: `since` (/played at the pledge), `seen` (/played as last recorded
  by the addon, kept current every second from the login /played plus
  session time), `untracked`.
- After login, once the save macro is read, the addon asks for /played (its
  own request isn't printed in chat). No answer: it asks again, 3 tries 30 s
  apart, then says this session will be checked at the next login. Gap = /played now − `seen`. Gaps of
  2 min or less are ignored; others add to `untracked`. Only the first
  /played of a session is assessed.
- Allowed: the larger of 2 h or 2% of the play since the pledge. Going over
  **breaks the oath**; a new oath starts a fresh record.
- Oaths from before this version start verification on first login.

## Saved pledge (`Save.lua`)

The record is kept in a character macro, `HonorBound Save`, because macros
are stored on Blizzard's servers and addon data isn't:

```
#HonorBound save data. Do not edit or delete this macro: a changed line is ignored and your pledge may be lost.
#HB3 l=12;s=40210;p=183342;u=95;n=41;h=4ACF1B72A61A7A37
```

- `l` level (0 = not sworn: a break is saved too, the macro is never
  deleted), `s` since, `p` seen, `u` untracked, `n` write counter, `h` a
  hash of all of it plus the character's GUID (hashed twice, so a one-second
  change scrambles it). Hand edits and macros copied to another character are
  rejected; the formula ships with the addon, so this stops casual edits, not
  a determined cheater, and an old copy of the line stays valid.
- Written on swear, break and a counted gap, every 2 min while sworn, and at
  logout; never in combat (it waits). Each write bumps the counter. Addons
  can only write SavedVariables at logout or /reload (why the Hardcore addon
  loses whole sessions to crashes); the macro is written during play.
- At login, once macros are loaded (`UPDATE_MACROS`, or 10 s after login):
  the higher counter wins. The macro's means another computer played since,
  so its record is adopted (its session isn't a gap); this computer's means a
  change here never reached the macro (e.g. a break in combat, then a
  reload), so it's written now. An edited macro is ignored and rewritten; a
  missing one is recreated. No free character macro slot: a dialog like the
  pledge prompt asks for one to be cleared (Open macros / Retry / Not now);
  meanwhile the record is local only. `/honor save` tries again.
- A crash or disconnect loses at most the 2 min since the last write, which
  the 2 min gap rule ignores.

## Development and validation

The distributable addon is in `HonorBound/`; the vector artwork is in
`art/`. To rebuild a TGA:
`rsvg-convert -w 128 -h 128 art/X.svg -o art/X.png && magick art/X.png -compress none HonorBound/Media/X.tga`.

Run `lua tests/run.lua` or `luajit tests/run.lua` from this directory. The
simulated-client tests cover the protocol, the oath, grace and breaking,
peer flag checks, crest placement, nameplates, settings, whisper probes to
everyone, rate-limit reports, chat crests and simulation. They don't replace
testing in game.
