#!/bin/bash
echo "Downloading Hel-K..."

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
			n=1
			while [ -f "${rel}.backup${n}" ]; do
				n=$((n + 1))
			done
			mv "$rel" "${rel}.backup${n}"
			cp "$src" "$rel"
			echo -e "\e[33mUPDATED: $rel (created backup $n)\e[0m"
		fi
	else
		dir=$(dirname "$rel")
		[ -n "$dir" ] && mkdir -p "$dir"
		cp "$src" "$rel"
		echo -e "\e[32mNEW: $rel\e[0m"
	fi
done

# Generate manifest
find New-Hel-K-main -type f | while read -r f; do
	echo "${f#New-Hel-K-main/}"
done > helk_manifest.txt

# Cleanup
rm -rf New-Hel-K-main
read -n 1 -s -r -p "Done!"