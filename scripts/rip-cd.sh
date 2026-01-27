#!/usr/bin/env bash

set -e

RIP_DIR="/tmp/ripz"
CDROM="/dev/cdrom"

echo "=== CD Ripper to FLAC with Beets Import ==="
echo ""

# Check for CD drive
if [ ! -e "$CDROM" ]; then
  echo "Error: No CD drive found at $CDROM"
  exit 1
fi

# Check for required tools
for cmd in cdparanoia flac beet cd-discid; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: $cmd not found. Install required packages."
    exit 1
  fi
done

# Create/clean rip directory
rm -rf "$RIP_DIR"
mkdir -p "$RIP_DIR/wav"

# Check for CD
if ! cdparanoia -Q 2>&1 | grep -q "^[[:space:]]*[0-9]"; then
  echo "Error: No audio CD detected in drive"
  exit 1
fi

echo "Audio CD detected"
echo ""

# Get CD info
DISCID=$(cd-discid $CDROM 2>/dev/null | awk '{print $1}')
echo "Disc ID: $DISCID"
echo ""

# Rip all tracks
echo "Ripping tracks..."
cd "$RIP_DIR/wav"
cdparanoia -B

echo ""
echo "Encoding to FLAC..."
mkdir -p "$RIP_DIR/flac"

for wav in *.wav; do
  if [ -f "$wav" ]; then
    tracknum=$(echo "$wav" | sed 's/track\([0-9]*\)\.cdda\.wav/\1/')
    flac -8 --verify --output-name="../flac/track${tracknum}.flac" "$wav"
    echo "Encoded: track${tracknum}.flac"
  fi
done

# Clean up WAV files
rm -rf "$RIP_DIR/wav"

echo ""
echo "Importing to beets..."
cd "$RIP_DIR/flac"
beet import .

echo ""
echo "=== Complete ==="
echo "Ripped files are in: $RIP_DIR/flac"
echo "To clean up: rm -rf $RIP_DIR"
echo ""

# Optional: eject CD
read -p "Eject CD? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  eject $CDROM
  echo "CD ejected"
fi
