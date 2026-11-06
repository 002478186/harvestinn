#!/usr/bin/env bash
# Combine all PNGs in a folder into one sheet.png (needs rsvg-convert).
cd "$1" || exit 1
files=( $(ls *.png | grep -v sheet.png) ); n=${#files[@]}; W=405; H=720
svg="<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' width='$((W*n))' height='$H'>"
for i in "${!files[@]}"; do svg+="<image x='$((i*W))' y='0' width='$W' height='$H' xlink:href='${files[$i]}'/>"; done
echo "$svg</svg>" > sheet.svg && rsvg-convert sheet.svg -o sheet.png && rm sheet.svg && echo "$1/sheet.png (${files[*]})"
