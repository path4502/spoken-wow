#!/usr/bin/env bash
# Installs Spoken for 3.3.5 and Spoken's voice packs into one or more 3.3.5 clients.
#
#   wotlk/install.sh <unzipped packs dir> <WoW folder> [<WoW folder>...]
#
# <unzipped packs dir> holds the pack folders as upstream's zips unpack them
# (SpokenQuestsAudioAlliance, ..., SpokenPlacesAudio, SpokenReadablesAudio, SpokenBossesAudio).
# Each pack is prepared once, in place, then copied:
#   * every .toc's Interface line is set to 30300, so the client does not call it out of date;
#   * the quest packs' .ogg recordings are converted to .mp3 (needs ffmpeg), and Module.lua is
#     pointed at .mp3. The 3.3.5 client plays .mp3 and .wav; .ogg is not certain to play.
# The addon itself is copied from wotlk/Spoken. Old copies of both are replaced.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
packs="${1:?usage: install.sh <unzipped packs dir> <WoW folder>...}"
shift
[ $# -ge 1 ] || { echo "name at least one WoW folder" >&2; exit 1; }

jobs="$(nproc 2>/dev/null || echo 4)"

prepare() {
	local dir="$1"
	for toc in "$dir"/*.toc; do
		sed -i 's/^## Interface:.*/## Interface: 30300/' "$toc"
	done
	if [ -f "$dir/Module.lua" ] && grep -q '\.ogg' "$dir/Module.lua"; then
		command -v ffmpeg >/dev/null || { echo "ffmpeg is needed to convert $dir" >&2; exit 1; }
		local count
		count=$(find "$dir" -name '*.ogg' | wc -l)
		echo "converting $count recordings in $(basename "$dir") to mp3..."
		find "$dir" -name '*.ogg' -print0 | xargs -0 -P "$jobs" -n 16 sh -c '
			for f do
				out="${f%.ogg}.mp3"
				if [ ! -s "$out" ]; then
					ffmpeg -nostdin -loglevel error -y -i "$f" -codec:a libmp3lame -b:a 96k "$out.tmp.mp3" && mv "$out.tmp.mp3" "$out"
				fi
				[ -s "$out" ] && rm -f "$f"
			done' sh
		left=$(find "$dir" -name '*.ogg' | wc -l)
		[ "$left" -eq 0 ] || { echo "$left recordings in $dir did not convert" >&2; exit 1; }
		sed -i 's/\.ogg\]\]/.mp3]]/g' "$dir/Module.lua"
	fi
}

for dir in "$packs"/*/; do
	dir="${dir%/}"
	ls "$dir"/*.toc >/dev/null 2>&1 || continue
	prepare "$dir"
done

for wow in "$@"; do
	addons="$wow/Interface/AddOns"
	mkdir -p "$addons"
	echo "installing into $addons"
	rm -rf "$addons/Spoken"
	cp -r "$here/Spoken" "$addons/Spoken"
	for dir in "$packs"/*/; do
		dir="${dir%/}"
		name="$(basename "$dir")"
		ls "$dir"/*.toc >/dev/null 2>&1 || continue
		rm -rf "$addons/$name"
		cp -r "$dir" "$addons/$name"
	done
done
echo done
