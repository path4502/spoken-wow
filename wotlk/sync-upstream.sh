#!/usr/bin/env bash
# Copies upstream Spoken's data files into the 3.3.5 addon, unchanged.
# Run after merging upstream's master into wotlk-3.3.5:
#   git fetch upstream && git merge upstream/master && wotlk/sync-upstream.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../addons"
dst="$here/Spoken/Upstream"
copy() { mkdir -p "$(dirname "$dst/$2")"; cp "$src/$1" "$dst/$2"; }

copy Spoken_Quests/Gossip/Aliases.lua        Quests/Aliases.lua
copy Spoken_Quests/FollowupLines.lua         Quests/FollowupLines.lua
copy Spoken_Quests/ChatterLines.lua          Quests/ChatterLines.lua
copy Spoken_Quests/Data/QuestText.lua        Quests/QuestText.lua
copy Spoken_Readables/Checksum.lua           Readables/Checksum.lua
copy Spoken_Readables/Data/Books.lua         Readables/Books.lua
copy Spoken_Places/Data/enUS/Zones.lua       Places/Zones.lua
copy Spoken_Places/Data/enUS/Subzones.lua    Places/Subzones.lua
copy Spoken_Places/Data/AreaZones.lua        Places/AreaZones.lua
copy Spoken_Places/Data/ForeverAreas.lua     Places/ForeverAreas.lua
copy Spoken_Bosses/Data/Bosses.lua           Bosses/Bosses.lua
copy Spoken_Bosses/Data/Creatures.lua        Bosses/Creatures.lua
copy Spoken_Bosses/Data/Stories.lua          Bosses/Stories.lua
# The words a recording actually says. Upstream rewrites lore and boss stories after a voice pack
# is recorded, so master's text can be newer than the audio. The text at the commit each installed
# pack was released from is loaded after master's and wins wherever it has an entry. Set these to
# the tags of the packs you install (upstream's releases: places-audio/vX, bosses-audio/vX).
PLACES_TAG="${PLACES_TAG:-places-audio/v2.1.0}"
BOSSES_TAG="${BOSSES_TAG:-bosses-audio/v1.0.0}"
remote="${UPSTREAM_REMOTE:-https://github.com/rusty-key/spoken-wow}"
recorded() { # tag, path in repo, destination under Upstream/
	git -C "$here/.." rev-parse -q --verify "refs/tags/$1" >/dev/null \
		|| git -C "$here/.." fetch -q --depth 1 "$remote" "refs/tags/$1:refs/tags/$1"
	git -C "$here/.." show "$1:$2" > "$dst/$3"
}
recorded "$PLACES_TAG" addons/Spoken_Places/Data/enUS/Zones.lua    Places/ZonesRecorded.lua
recorded "$PLACES_TAG" addons/Spoken_Places/Data/enUS/Subzones.lua Places/SubzonesRecorded.lua
recorded "$BOSSES_TAG" addons/Spoken_Bosses/Data/Stories.lua       Bosses/StoriesRecorded.lua

cp "$here/../LICENSE" "$here/Spoken/LICENSE"
cp "$here/../THIRD_PARTY.md" "$here/Spoken/THIRD_PARTY.md"
echo "upstream data copied into $dst"
