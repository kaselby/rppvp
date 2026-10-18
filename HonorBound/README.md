# HonorBound

WoW Forever has no RP-PvP realms, so this addon makes the commitment a
community badge instead. Each character swears an oath to stay flagged for
PvP. Sworn players wear a faction crest on their player, target and focus
frames and beside their name on nameplates, and other members can see it. There are
no ranks or scores: you're either sworn and flagged, or you aren't.

## Install and share

Extract `HonorBound.zip` into your Forever client's `Interface/AddOns`
folder. Forever runs from the **`_classic_beta_`** folder, not
`_classic_era_`, so the result must be
`World of Warcraft/_classic_beta_/Interface/AddOns/HonorBound/HonorBound.toc`.
To find the folder, click the gear next to Play in the Battle.net app and
choose **Show in Explorer** (Windows) or **Show in Finder** (Mac). Create the
`Interface/AddOns` folders if they don't exist yet.
Fully restart WoW and enable **HonorBound** at character select. Share
the ZIP with your community: both players need the addon to see each other's
crests. HonorBound replaces the separate RP-PvP addon; don't run both,
or you'll get two sets of flag prompts.

## The oath

- On a character's first login you're offered the oath. Already flagged?
  Click **Swear the oath**. Not flagged? **Flag and swear** flags you
  (Blizzard only lets a real click change the flag) and swears you in.
- Once sworn and flagged, **Disable** in the portrait PvP menu is greyed out.
- If anything unflags you (typing `/pvp`, entering a dungeon), you get 5
  minutes to reflag. The countdown carries over if you log out, and it pauses
  inside dungeons and raids, where you can't reflag; it starts fresh when you
  leave.
- The countdown also waits while you're away: if you're unflagged and haven't
  moved, turned, cast, fought or looted for 30 seconds, it holds until you do
  something again. Chatting doesn't count as activity.
- Reflagging takes no extra step: while you're unflagged, your next action
  bar key or click on an action bar button flags you and still uses the
  ability. Movement keys are never touched. If you don't use one within 30
  seconds, a popup with a flag button appears too. If you turned the flag
  off yourself with `/pvp`, the popup appears straight away. `/honor autoflag off`
  turns this off and goes straight to the popup.
  When it runs out, the oath breaks and your crest disappears. `/honor swear`
  takes it again.
- `/honor renounce confirm` gives the oath up voluntarily.

## The crest

A blue (Alliance) or red (Horde) shield with crossed swords **replaces the PvP
icon** on the player, target and focus frames. A smaller copy sits just left
of the name on sworn players' nameplates, and the same crest appears before
sworn players' names in chat, including whispers (both ways), yells and emotes
(faction read from their race; your own faction if unknown). Hover the crest
or the player for a "Sworn to RP-PvP" line. If their addon reports the level
they swore at, it reads "PvP pledged since level N" instead. That level is
self-reported (an honor-system record, reset when an oath breaks), and a claim
above the player's current level isn't shown.

A player wears the crest only when two things are true: their addon says
they're sworn, and the server reports them flagged right now (`UnitIsPVP`).
An unflagged player never shows a crest, whatever their addon claims.

Players from other realms you've met before show their crest as soon as you
see them, from their saved oath status, while the addon checks again in the
background. A "not sworn" answer removes it at once; two unanswered checks in
a row remove it too.

## Commands

- `/honor`: oath status, flag, sworn players heard from, channel status.
- `/honor swear`: take the oath on this character.
- `/honor renounce confirm`: give up the oath.
- `/honor autoflag on|off`: reflag on your next action bar key or click (on by default).
- `/honor plates`: toggle crests on nameplates.
- `/honor chat on|off`: toggle crests in chat.
- `/honor debug on|verbose|off`: discovery diagnostics for this session.
- `/honor sim 10` / `/honor sim off`: simulation for testing discovery (below).
- `/honor chatcheck`: report how this client's chat frames store lines (diagnoses chat crests).
- `/honor scale 1.2`: crest size, from 0.6 to 2.
- `/honor offset 0 0`: nudge the crest from the PvP icon position, in UI pixels.
- `/honor reset`: reset appearance settings.

## Discovery and compatibility

Discovery uses GUIDs, because Forever's surname-bearing character names can
differ between chat and unit frames. Forever's custom channels only reach one
backend realm (for example ClassicBetaPvP and ClassicBetaPvP2 each get their
own `HonorBound` channel), and addon `YELL`/`SAY` messages are refused, so
players from another realm are reached by hidden addon whispers. What one
player learns about another realm is shared once on their own realm's channel.
Forever names are "First Surname": whispers must go to `First-Surname`, the
form `UnitName` returns (surname in the realm slot). `First Surname-Realm`,
which `GetPlayerInfoByGUID` and incoming whisper senders give, bounces, so
every whisper address is normalized to the first form.

The protocol is version 2. Players still on 0.1.x won't show crests until
they update. Whispers don't cross factions, so cross-faction discovery isn't
supported. Custom unit-frame and nameplate replacements (such as Plater)
aren't supported, and Blizzard blocks addons from changing nameplates inside
dungeons. The oath is voluntary and enforced on your own client, not verified
by the server; only the flag check comes from the server.

## How discovery works

```
           YOUR REALM                                OTHER REALM
 ┌──────────────────────────────────┐          ┌──────────────────────────────────┐
 │ hidden channel "HonorBound"    │          │ hidden channel "HonorBound"    │
 │  • S/P status every 60 s          │          │  • S/P status every 60 s          │
 │  • Q "who is this?" (once each)   │          │  • Q "who is this?" (once each)   │
 │  • F "found X over there"         │          │  • F "found Y over there"         │
 │  • N "these have no addon"        │          │  • N "these have no addon"        │
 └───────────────┬──────────────────┘          └──────────────────┬───────────────┘
                 │       hidden whispers (WQ probe / WR reply)     │
                 └─────────────────────────────────────────────────┘
          group / guild messages (S/P, Q) cross realms when you share one
```

Within a realm everyone hears everyone on the channel. Between realms the
only path is a whisper, one player at a time, and the channel sharing lets one
player's whisper result serve their whole realm.

### What gets sent

| Message | Route | About | Sent when | Limits |
|---|---|---|---|---|
| `S\|2\|…` + `P\|1\|…` status and pledge level | Channel, group, guild | You | Login, 2 s after joining the channel, every 60 s, on oath/flag/group change | At most once per 3 s if unchanged. Always sent, still spends budget |
| `Q\|1\|<GUID>` "does this player use the addon?" | Channel, group, guild | An unknown player on **your realm** | Seen on a nameplate, target, focus, mouseover or tooltip, or in chat | Asked **once**. No announcement within 10 s: on the no-addon list for 2 h (saved, not shared). At most 1 a second, budget for every route |
| `WQ\|1\|…` probe, carries your status | Whisper | A player on **another realm**, same faction | Seen: remembered addon users first, then mouseover/target, chat, nameplates | Queue of 40, dropped after 30 s waiting, 1 whisper a second. Skipped if known (210 s + random 0-45 s, so a peer in view is refreshed before its 5 min expiry), awaiting a reply, or on the no-addon list |
| `WR\|1\|…` reply, carries your status | Whisper | Someone who probed you | A `WQ` arrives, even if your own probe to them is in flight | Sent before probes. At most 20 waiting, 1 per player per minute, dropped after 30 s |
| `F\|1\|…` "found this player on the other realm" | Channel | A player on another realm you just confirmed | After a `WQ`/`WR` exchange with them | Random 2-10 s wait; skipped if the same status was posted in the last 150 s. Spare budget only; a refused send pauses sharing for 2 min |
| `N\|1\|id,id,…` "no addon" list | Channel | Up to 15 players on another realm who didn't answer | 20-40 s after the first one is collected | Someone else's list resets your timer and removes duplicates. At most 60 waiting. Same 2 min pause on refusal |

### What happens when you receive each message

| You receive | Effect |
|---|---|
| `S` / `P` (channel, group, guild, instance) | Known peer for 5 min; clears any no-addon entry for them |
| `Q` asking about **you** | You re-announce, at most once per 5 s |
| `WQ` | Learn their status, remember them as an addon user (2 weeks), share a find, queue a reply |
| `WR` | Learn their status, remember them, share a find |
| `F` from your realm | Show their badge as a relayed status without probing; cancel your own post if it says the same |
| `N` from your realm | Mark those players no-addon for 30 min and drop them from your queue, unless you know they use the addon |
| Your own `F` / `N` echoing back | Ignored |

A badge shows only when the player is a known addon user, has sworn, was
heard from in the last 5 minutes (or, for a remembered user not yet heard from
this time, was sworn when last heard and hasn't missed two re-checks in a row),
**and** is PvP-flagged right now (`UnitIsPVP`). Chat can't check the flag.

### What gets remembered

| List | Holds | Lasts | Saved |
|---|---|---|---|
| Known players | Status of addon users heard from | 5 min | No |
| Remembered addon users | Whisper name and last oath status of confirmed users; probed first when seen again, crest shown meanwhile | 2 weeks | Yes |
| No addon | Players who didn't answer | 2 h (your own) / 30 min (shared) | Yes |
| Heard finds | Last find posted per player | 5 min | No |

Mistakes correct themselves: any message from a player (announcement, probe,
reply, or someone's find) removes them from the no-addon list. A player on
another realm whose reply was lost will probe you in turn within a few
minutes, and a same-realm player's next 60-second announcement clears them.

### Rate limits and priorities

The server allows roughly one addon message a second per prefix after a small
burst, with a stricter, undocumented limit on channels. HonorBound keeps
one budget for everything it sends: a burst of 5, then one message every 2
seconds, about half the server's allowance. Each second it sends, in order:

1. a waiting whisper reply, or else one probe;
2. a find or no-addon list, if budget is spare;
3. the regular status broadcast, when due;
4. `Q` questions for unknown same-realm players on screen.

Nothing optional is sent during encounter lockdown. In a crowded city the
traffic settles at a few messages a minute per player: each stranger is asked
once, the realm splits the work by probing in random order, and the listen-
before-posting rule keeps shared finds and lists at about the same rate no
matter how many players run the addon.

Debug: `/honor debug on` shows broadcasts, channel shares and a summary line
each minute; `/honor debug verbose` adds every whisper probe and reply. While
debugging, players without a real crest show a **light grey** crest while
they're being asked and a **dark grey** one once marked no-addon, and each
summary includes a coverage line over the nameplates in view:

`40 players on screen: 4 have the addon, 20 don't, 5 being asked, 11 waiting in line, 0 not asked. (Simulating 10% addon users.) On average after first seeing someone: asked in 18 s, answered in 21 s, ruled out in 49 s.`

Chat shows the same states while debugging or simulating: **light grey**
while being asked, **dark grey** once marked no-addon (`Media/CrestGrey.tga`,
tinted).

A stranger's first message prints before anyone knows whether they have the
addon. HonorBound remembers the last 300 chat lines by line ID and, when a
player's status changes (asked, answered, ruled out, shared, simulated),
rewrites the crest inside their name on lines already in chat, using the chat
frames' `TransformMessages`. So the first line gains its crest a second or two
after it appears. On clients without that method, or for lines the game keeps
hidden during encounters, nothing changes and the crest shows from the next
message on.

Debug lines are plain sentences with the time and a coloured first word —
**Sent** (yellow), **Heard** (green), **Couldn't send** (red, with the reason,
e.g. "the channel is busy, the game is throttling us"). `/honor debug on`
shows your status updates, shares, anything heard on the channel, failures and
the summaries; `/honor debug verbose` adds every probe, reply and message.

### Simulation

Few players run the addon yet, so almost every probe ends in the 30 s no-reply
timeout. `/honor sim N` makes N% of the players you ask answer like addon
users, 0.5-3 s after the real probe goes out, and wear a full crest on
nameplates, unit frames, tooltips and chat (whatever their PvP flag).
Everything else stays real: probes, the send budget, queue order, timeouts
and the saved and shared no-addon list. It turns debug on and prints the
coverage line every 15 s, so you can watch a crowd fill in at real speed.

- Who answers is a fixed hash of the player's GUID, not a random roll: every
  tester with the same N sees the same simulated users, with nothing to sync.
- Testers share simulated finds with each other as `FS|1|…` on the realm
  channel. A tester only accepts one if their own hash agrees; players not
  simulating (and older builds) ignore `FS`.
- Simulated users are never saved, never posted as real `F` finds, and a
  shared no-addon list can't hide them.
- `/honor sim off` removes simulated crests and keeps everything learned for
  real. `/honor sim` prints the coverage line.

## Development and validation

The distributable addon is in `HonorBound/`; the vector artwork is in
`art/`. To rebuild a TGA:
`rsvg-convert -w 128 -h 128 art/X.svg -o art/X.png && magick art/X.png -compress none HonorBound/Media/X.tga`.

Run `lua tests/run.lua` or `luajit tests/run.lua` from this directory. The
simulated-client tests cover the protocol, the oath, grace and breaking,
peer flag checks, crest placement, nameplates, settings, whisper probes, realm
sharing, same-realm queries, chat crests and simulation. They don't replace
testing in game.
