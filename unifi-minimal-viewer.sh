#!/bin/bash

# Define colors and logging function
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 1. Clean up to make space
log "Cleaning up to make space..."
sudo apt clean
sudo apt autoclean
sudo apt autoremove -y

# 2. Install minimal required packages
log "Installing minimal required packages..."
sudo apt update
sudo apt install -y vlc python3-vlc python3-pip --no-install-recommends

# 3. Create a simple Python camera viewer
log "Creating Python-VLC camera viewer..."
cat > ~/simple_viewer.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
import time
import vlc

# Simple VLC viewer for RTSP streams
RTSP_URLS_FILE = os.path.expanduser("~/rtsp_urls.txt")
ROTATION_INTERVAL = 60  # seconds

def main():
    # Check if file exists
    if not os.path.exists(RTSP_URLS_FILE):
        print(f"Error: {RTSP_URLS_FILE} not found")
        sys.exit(1)
    
    # Load URLs
    with open(RTSP_URLS_FILE, 'r') as f:
        urls = [line.strip() for line in f if line.strip().startswith('rtsp://')]
    
    if not urls:
        print("No RTSP URLs found in file")
        sys.exit(1)
    
    print(f"Found {len(urls)} camera URLs")
    
    # Initialize VLC
    instance = vlc.Instance('--no-audio --fullscreen')
    player = instance.media_player_new()
    player.set_fullscreen(True)
    
    # Main loop
    while True:
        for url in urls:
            print(f"Playing: {url}")
            
            # Create media and play
            media = instance.media_new(url)
            player.set_media(media)
            player.play()
            
            # Wait for playback to start
            time.sleep(2)
            
            # Wait for rotation interval
            time.sleep(ROTATION_INTERVAL)

if __name__ == "__main__":
    main()
EOF

chmod +x ~/simple_viewer.py

# 4. Create a template for RTSP URLs
cat > ~/rtsp_urls.txt << 'EOF'
# Camera 1
rtsp://USERNAME:PASSWORD@HOST:7447/CAMERA_ID_1

# Camera 2
rtsp://USERNAME:PASSWORD@HOST:7447/CAMERA_ID_2

# Note: Replace with your actual values
EOF

log "Setup complete!"
log "Edit ~/rtsp_urls.txt with your actual camera URLs"
log "Run with: python3 ~/simple_viewer.py"
