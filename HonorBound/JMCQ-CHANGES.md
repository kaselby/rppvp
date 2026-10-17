# HonorBound 0.2.0-jmcq-pledge3-channels-debug

Based on pledge3. Adds opt-in local diagnostics and enables
chat badges for CHAT_MSG_CHANNEL: General, Trade, LookingForGroup and other
ordinary channels. No Prat adapter, chat probes, or added discovery behavior.
/honor debug on|off logs timer broadcasts, send API results and incoming status.
Logging is session-only and adds no network traffic. Accepted does not mean delivered.

Extract HonorBound into Interface/AddOns with WoW closed, replacing the addon
files. Restart WoW. Character saves are not included and should not be deleted.
Chat icons use recently advertised pledge status; /honor chat on|off controls them.
Pledge level records and their honor-system limitations are unchanged.

Validation: version-3 baseline checked against the previous release ZIP; runtime
code compared to that baseline. Automated tests cover the enabled channel event.
In-game check: without Prat, confirm /say, guild/party and General/Trade badges
with another pledged player after status announcements arrive. First-line badges
are not guaranteed. Prat compatibility is intentionally back to version 3.

# whisper1 (on top of pledge3-channels-debug)

Players on other realms can't hear the hidden channel, so the addon now asks the
ones you actually meet with a hidden addon whisper: mouseover/target first, then
chat speakers (say, yell, emote, public channels, whispers), then nameplates.
Same-realm players still use the channel, group and guild as before.

- One message each way: the probe carries your status, the reply carries theirs.
- Shared budget for all sends: burst of 5, then one message per 2 seconds.
- At most one whisper per second; replies before probes.
- Probe queue capped at 40, stale after 30 s. Reply queue capped at 20, one reply
  per player per minute. No reply in 30 s: that player isn't asked for 15 min.
- Peers still in view are refreshed shortly before their 180 s status expires.
- Opposite faction is never probed. Nothing is sent during encounter lockdown.
- "No player named ..." errors from probes are hidden.
- A status that claims another player's GUID is ignored.
- /honor debug shows whisper TX/RX and queue sizes.
- Fixed: lastPledgePayload was leaking as a global.

# share1 (on top of whisper1)

Realm sharing: what one player learns about another realm is posted once on
their own realm's hidden channel, so nobody else on that realm has to ask.

- Finds: a confirmed player from another realm is posted as F|1|... after a
  random 2-10 s wait, skipped if someone else posted the same news first.
  Reposted only on a status change or after 150 s, to refresh the realm.
- Relayed finds show the badge (still only while the player is PvP-flagged)
  and are not probed until they go stale.
- No addon: silent players are collected for 20-40 s and posted in batches of
  up to 15 (N|1|...). Hearing someone else's list resets your own timer, so
  the more players on the realm, the less often each one posts.
- Shared lists never hide a player you know has the addon.
- Channel posts only use spare budget; a refused channel send (e.g. channel
  throttle, result 8) pauses sharing for 2 minutes. Whispers carry on.
- Probes pick at random among equal priorities, so a realm spreads out.
- Saved across reloads: addon users (2 weeks, probed first when seen) and
  players without it (2 h own, 30 min shared).
- Debug: /honor debug on shows broadcasts, shares and a one-line summary each
  minute; /honor debug verbose also shows every whisper probe and reply.

# share2 (on top of share1)

- Same-realm questions (Q|1) are asked once per player. No announcement within
  10 s puts them on the no-addon list for 2 h (saved, not shared). Before, an
  unknown same-realm player was re-asked every 15 s for as long as they were
  on screen, which was most of the channel's traffic in cities.
- Hearing any status from a player clears their no-addon entry immediately.
- Chat names now wear the faction crest used on frames and nameplates instead
  of the neutral crossed swords. Faction comes from the sender's race, falling
  back to your own.
- README: full breakdown of messages, rules, caches and rate limits.

# 0.3.0: renamed to HonorBound

- Addon, folder, saved variables (HonorBoundDB, HonorBoundCharDB), hidden
  channel (HonorBound) and message prefix (HONORBOUND1) are all renamed.
  Badge of Honor builds and HonorBound builds can't see each other: everyone
  needs 0.3.0.
- Commands are /honor and /honorbound.
- Saved oaths don't carry over by themselves: copy WTF/.../SavedVariables/
  BadgeOfHonor.lua to HonorBound.lua (both the account and each character's
  folder) and rename BadgeOfHonorDB/BadgeOfHonorCharDB inside, with WoW closed.

# 0.3.1: simulation and debug overlay

- /honor sim N: N% of the players you ask answer as addon users 0.5-3 s after
  the real probe, with a full crest on nameplates, unit frames, tooltips and
  chat. Probes, budget, timeouts and the no-addon list stay real. Who answers
  is a fixed GUID hash, so testers with the same N see the same players.
  Testers share simulated finds as FS (ignored by everyone not simulating).
- Debug overlay: faint grey crest while a player is being asked, solid grey
  once marked no-addon.
- Coverage line (every minute, every 15 s while simulating): nameplates by
  state and average seen-to-probe / seen-to-answer / seen-to-no-addon times.

# 0.3.2: readable debug output

- Debug lines are plain sentences with the clock time, player names instead
  of IDs, "the realm channel"/"your guild" instead of route codes, and a
  coloured first word: Sent, Heard, Couldn't send (with the reason in words).
- Summary and coverage lines rewritten as sentences with correct plurals;
  share counts only include sends that went through.
- Fixed: when the channel refused a status update it was retried every
  second; it now waits 10 s.

# 0.3.3

- Fixed: in simulation, players already on the no-addon list (from earlier in
  the session or a shared list) were never asked again, so simulated users
  among them stayed solid grey. Simulated users now skip the list; the list
  itself is unchanged for everyone else.
