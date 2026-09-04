#!/bin/bash
echo "Downloading Hel-K..."
haveJq=true
command -v jq >/dev/null 2>&1 || {
	echo "jq is required for commit lookup. Install with: sudo apt install jq"
	haveJq=false
}

owner="Helwor"
repo="New-Hel-K"

# Build curl auth args once (optional GITHUB_TOKEN support, same as the Windows version)
curl_auth=(-H "User-Agent: Hel-K-Updater")
if [ -n "$GITHUB_TOKEN" ]; then
	curl_auth+=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

# Returns "date - message (sha)" for the single most recent commit touching a path
get_last_commit() {
	local rel="$1"
	local response
	response=$(curl -s -G "https://api.github.com/repos/$owner/$repo/commits" \
		"${curl_auth[@]}" \
		--data-urlencode "path=$rel" \
		--data-urlencode "sha=main" \
		--data-urlencode "per_page=1")

	if [ "$(echo "$response" | jq -r 'type' 2>/dev/null)" != "array" ]; then
		echo "commit info unavailable (rate limit or network error)"
		return
	fi
	if [ "$(echo "$response" | jq 'length')" -eq 0 ]; then
		echo "no commit found for this file"
		return
	fi
	echo "$response" | jq -r '.[0] | "\(.commit.author.date) - \((.commit.message | split("\n")[0])) (\(.sha[0:7]))"'
}

# Lists every commit touching a path that is newer than local_epoch,
# or reports "up to date" with the last commit if none are newer
show_commits_since() {
	local rel="$1"
	local local_epoch="$2"
	local response

	response=$(curl -s -G "https://api.github.com/repos/$owner/$repo/commits" \
		"${curl_auth[@]}" \
		--data-urlencode "path=$rel" \
		--data-urlencode "sha=main" \
		--data-urlencode "per_page=30")

	if [ "$(echo "$response" | jq -r 'type' 2>/dev/null)" != "array" ]; then
		echo -e "\e[36m  commit info unavailable (rate limit or network error)\e[0m"
		return
	fi

	local count
	count=$(echo "$response" | jq 'length')
	if [ "$count" -eq 0 ]; then
		echo -e "\e[36m  No commit found for this file\e[0m"
		return
	fi

    local newer_lines=()
    while IFS=$'\t' read -r cdate cmsg csha; do
        local cepoch
        cepoch=$(date -d "$cdate" +%s)
        cdate="${cdate/T/ }"
        cdate="${cdate%Z}"
        if [ "$cepoch" -gt "$local_epoch" ]; then
            newer_lines+=("    $cdate - $cmsg (${csha:0:7})")
        fi
    done < <(echo "$response" | jq -r '.[] | [.commit.author.date, (.commit.message | split("\n")[0]), .sha] | @tsv')

    if [ "${#newer_lines[@]}" -gt 0 ]; then
        echo -e "\e[36m  ${#newer_lines[@]} commit(s) since your local version:\e[0m"
        printf "\e[36m%s\e[0m\n" "${newer_lines[@]}"
    else
        local last
        last=$(echo "$response" | jq -r '.[0] | [.commit.author.date, (.commit.message | split("\n")[0]), .sha] | @tsv')
        IFS=$'\t' read -r ldate lmsg lsha <<< "$last"
        ldate="${ldate/T/ }"
        ldate="${ldate%Z}"
        echo -e "\e[36m  Local file modified by user, set back to last commit:\e[0m"
        echo -e "\e[36m    $ldate - $lmsg (${lsha:0:7})\e[0m"
    fi
}

# Download and extract
wget -q --show-progress -O luaui.zip 'https://github.com/Helwor/New-Hel-K/archive/main.zip' && echo "" || {
    echo "Download failed. Aborting."
    exit 1
}

unzip -qo luaui.zip || {
	echo "Failed to extract package. Aborting."
	rm -f luaui.zip
	exit 1
}
rm -f luaui.zip

[ -f "New-Hel-K-main/.gitignore" ] && rm "New-Hel-K-main/.gitignore"

if [ ! -d "New-Hel-K-main" ]; then
	echo "Failed to extract package. Aborting."
	exit 1
fi

# Handle removed files

if [ -f "helk_manifest.txt" ]; then
	echo "Checking removed files..."
	while IFS= read -r f; do
		new_path="New-Hel-K-main/$f"
		if [ ! -f "$new_path" ] && [ -f "$f" ]; then
			n=1
			while [ -f "${f}.removed${n}" ]; do
				n=$((n + 1))
			done
			mv "$f" "${f}.removed${n}"
			echo -e "\e[31mREMOVED: $f\e[0m"
		fi
	done < helk_manifest.txt
fi

# Update files
echo "Checking existing files..."
find New-Hel-K-main -type f | while read -r src; do
	rel="${src#New-Hel-K-main/}"
	if [ -f "$rel" ]; then
		if ! cmp -s <(tr -d '\r' < "$src") <(tr -d '\r' < "$rel"); then
			local_epoch=$(stat -c %Y "$rel")
			n=1
			while [ -f "${rel}.backup${n}" ]; do
				n=$((n + 1))
			done
			mv "$rel" "${rel}.backup${n}"
			cp "$src" "$rel"
			echo -e "\e[33mUPDATED: $rel (created backup $n)\e[0m"
			if $haveJq; then
				show_commits_since "$rel" "$local_epoch"
			fi
		fi
	else
		dir=$(dirname "$rel")
		[ -n "$dir" ] && mkdir -p "$dir"
		cp "$src" "$rel"
		echo -e "\e[32mNEW: $rel\e[0m"
		if $haveJq; then
			echo -e "\e[36m  Last commit: $(get_last_commit "$rel")\e[0m"
		fi
	fi
done

# Generate manifest
find New-Hel-K-main -type f | while read -r f; do
	echo "${f#New-Hel-K-main/}"
done > helk_manifest.txt

# Cleanup
rm -rf New-Hel-K-main
read -n 1 -s -r -p "Done!"