#!/bin/bash
# Download CC0 reference images from Unsplash + Pexels for ad style reference.
# All images downloaded here are free for commercial use (CC0-ish).
# These are REFERENCE images for style guidance, NOT the final ad assets.
# Run: bash download_references.sh

set -e
cd "$(dirname "$0")"

# Helper to download a URL with retries; skip if file already exists.
download() {
  local url="$1"
  local out="$2"
  if [ -f "$out" ]; then
    echo "  skip (exists): $out"
    return 0
  fi
  echo "  downloading: $out"
  curl -fsSL -o "$out" "$url" || echo "  FAILED: $url"
}

# --- Disc golf real-world reference (Unsplash) ---
# Note: Unsplash direct URLs change; use their CDN format. Below are stable
# image IDs we picked manually. If a link fails, browse unsplash.com manually.

# Disc golf player throwing
download "https://images.unsplash.com/photo-1572116469696-31de0f17cc34?w=1200&q=80" "disc_thrower_1.jpg"
download "https://images.unsplash.com/photo-1622465413779-8af65586e1ef?w=1200&q=80" "disc_thrower_2.jpg"
download "https://images.unsplash.com/photo-1623685307907-fe70cdc8e7ae?w=1200&q=80" "disc_basket_1.jpg"

# Forest paths
download "https://images.unsplash.com/photo-1448375240586-882707db888b?w=1200&q=80" "forest_1.jpg"
download "https://images.unsplash.com/photo-1473773508845-188df298d2d1?w=1200&q=80" "forest_2.jpg"

# Lake / water carries
download "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1200&q=80" "lake_1.jpg"
download "https://images.unsplash.com/photo-1505820013142-f86a3439c5b2?w=1200&q=80" "lake_2.jpg"

# Desert open spaces
download "https://images.unsplash.com/photo-1473580044384-7ba9967e16a0?w=1200&q=80" "desert_1.jpg"
download "https://images.unsplash.com/photo-1547234935-80c7145ec969?w=1200&q=80" "desert_2.jpg"

# Locker room / sports prep
download "https://images.unsplash.com/photo-1517438476312-10d79c5f25af?w=1200&q=80" "locker_1.jpg"
download "https://images.unsplash.com/photo-1571019613540-996a69725660?w=1200&q=80" "locker_2.jpg"

# Phone gameplay
download "https://images.unsplash.com/photo-1573225342350-16731dd9bf3d?w=1200&q=80" "phone_gaming_1.jpg"

echo ""
echo "Done. If any FAILED, browse Unsplash manually:"
echo "  https://unsplash.com/s/photos/disc-golf"
echo "  https://unsplash.com/s/photos/forest-path"
echo "  https://unsplash.com/s/photos/desert-landscape"
echo ""
echo "All files saved in: $(pwd)"
