# Spoken for 3.3.5a (WotLK)

A port of [Spoken](https://github.com/rusty-key/spoken-wow) to the 3.3.5a client, for an
AzerothCore server that recreates WoW Forever. It plays Spoken's own voice packs unchanged
(apart from the conversion below): quest dialogue, NPC gossip, follow-up lines and world chatter,
books and letters, zone and subzone lore, and dungeon boss stories.

## What is here

| Path | What |
|---|---|
| `Spoken/` | The 3.3.5 addon. Install as `Interface/AddOns/Spoken`. |
| `Spoken/Upstream/` | Upstream's data files (quest text, chatter and follow-up lines, books, place lore, boss stories), copied unchanged. |
| `sync-upstream.sh` | Re-copies those files after a merge from upstream. |
| `install.sh` | Prepares the voice packs for 3.3.5 and installs them with the addon. |
| `tests/` | A stand-in for the 3.3.5 API and checks of every kind of line: `lua5.1 wotlk/tests/run.lua`. |

## Installing

1. Download the English voice packs from upstream's GitHub releases (newest of each):
   `quests-audio/` (SpokenQuestsAudioAll), `places-audio/`, `readables-audio/`, `bosses-audio/`.
   Unzip them all into one folder.
2. `wotlk/install.sh <that folder> "<WoW folder>" ["<another WoW folder>"...]`

`install.sh` sets every pack's `.toc` Interface to 30300 and converts the quest packs from
.ogg to .mp3 (needs `ffmpeg`), because the 3.3.5 client plays .mp3 and .wav.

## Updating from upstream

```sh
git remote add upstream https://github.com/rusty-key/spoken-wow   # once
git fetch upstream
git checkout master && git merge --ff-only upstream/master && git push   # or "Sync fork" on GitHub
git checkout wotlk-3.3.5 && git merge master
wotlk/sync-upstream.sh && lua5.1 wotlk/tests/run.lua
```

Everything 3.3.5-specific lives under `wotlk/`, so the merge does not conflict. New voice packs
need `install.sh` again.

## How it differs from upstream

The 3.3.5 client lacks most of what upstream's code is built on, so the player, the windows and
the settings are written again here, smaller:

- **Stopping a line.** 3.3.5 cannot stop a sound. A line is played as music instead (the
  approach of AI_VoiceOver's 3.3.5 backport): the game music fades out, the line plays, and
  `silence.wav` cuts it when it ends or is stopped. Turn "Play on the music channel" off to
  play lines as sounds, which cannot be stopped.
- **Quest ids.** 3.3.5 has no `GetQuestID()` in the quest window; the quest is found from its
  title, giver and text through the packs' `QuestIDLookup`, as upstream does on old clients.
- **Places.** Upstream keys zones by modern uiMapIDs. Here a zone is found by its name, and a
  subzone by its normalised name under it, from the same lore files.
- **Bosses.** There is no `ENCOUNTER_END`; a boss's story is told when the combat log reports
  its death, once per character.
- **Narrator.** Subtitles, a small window with the speaker's 3D portrait, or voice only.
  Not ported: the large window, the DialogueUI window, Azeroth's Compendium, the contribute
  and report buttons, non-English languages.

Settings: Interface > AddOns > Spoken, or `/sp`. `/sp help` lists the commands.
