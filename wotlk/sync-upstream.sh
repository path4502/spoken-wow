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
cp "$here/../LICENSE" "$here/Spoken/LICENSE"
cp "$here/../THIRD_PARTY.md" "$here/Spoken/THIRD_PARTY.md"
echo "upstream data copied into $dst"
