# HonorBound: technical notes

For contributors. Player docs are in the [README](../README.md).

## Discovery and compatibility

There is no hidden channel. Everyone you see (nameplates, mouseover,
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
  throttling us") and the server's own throttle notice are **always**
  reported, debug or not: the first at once, then one summary every 10 s.
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

## Development and validation

The distributable addon is in `HonorBound/`; the vector artwork is in
`art/`. To rebuild a TGA:
`rsvg-convert -w 128 -h 128 art/X.svg -o art/X.png && magick art/X.png -compress none HonorBound/Media/X.tga`.

Run `lua tests/run.lua` or `luajit tests/run.lua` from this directory. The
simulated-client tests cover the protocol, the oath, grace and breaking,
peer flag checks, crest placement, nameplates, settings, whisper probes to
everyone, rate-limit reports, chat crests and simulation. They don't replace
testing in game.
