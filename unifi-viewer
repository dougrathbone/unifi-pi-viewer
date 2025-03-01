#!/bin/bash
# Raspberry Pi 3B UniFi Viewport Setup Guide - OMXPlayer Version
# This lightweight setup uses OMXPlayer for optimal performance on Raspberry Pi 3B

# 1. Start with a fresh Raspberry Pi OS installation
# Download Raspberry Pi OS Lite (32-bit) from https://www.raspberrypi.org/software/operating-systems/
# Flash it to your microSD card using the Raspberry Pi Imager

# 2. Set up your Raspberry Pi for headless operation (optional but recommended)
# Create a file named 'ssh' in the boot partition
# Create a file named 'wpa_supplicant.conf' in the boot partition with:
# 
# country=US
# ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
# update_config=1
# 
# network={
#     ssid="YOUR_WIFI_SSID"
#     psk="YOUR_WIFI_PASSWORD"
# }

# 3. Boot your Raspberry Pi and update the system
sudo apt update
sudo apt full-upgrade -y

# 4. Install required packages (OMXPlayer should be pre-installed, but make sure)
sudo apt install -y omxplayer ffmpeg jq curl

# 5. Create a script to retrieve UniFi RTSP URLs
cat > ~/get_unifi_streams.sh << 'EOF'
#!/bin/bash

# UniFi Protect connection settings
UNIFI_HOST="YOUR_UNIFI_HOST_OR_IP"
UNIFI_PORT="443"
UNIFI_USERNAME="YOUR_UNIFI_USERNAME"
UNIFI_PASSWORD="YOUR_UNIFI_PASSWORD"

# Login to UniFi Protect and get authentication token
echo "Logging in to UniFi Protect..."
RESPONSE=$(curl -s -k -X POST -H "Content-Type: application/json" \
    -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\"}" \
    "https://$UNIFI_HOST:$UNIFI_PORT/api/auth/login")

# Extract authentication token
TOKEN=$(echo $RESPONSE | jq -r '.access_token // .Authorization')
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "Failed to authenticate with UniFi Protect"
    exit 1
fi

# Get camera list
echo "Getting camera list..."
CAMERAS=$(curl -s -k -X GET -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    "https://$UNIFI_HOST:$UNIFI_PORT/api/cameras")

# Extract camera IDs and names
echo $CAMERAS | jq -r '.[] | "\(.id) \(.name)"' > ~/camera_list.txt

# Generate RTSP URLs
echo "Generating RTSP URLs..."
while read -r id name; do
    echo "# $name"
    echo "rtsp://$UNIFI_USERNAME:$UNIFI_PASSWORD@$UNIFI_HOST:7447/$id"
    echo ""
done < ~/camera_list.txt > ~/rtsp_urls.txt

echo "RTSP URLs saved to ~/rtsp_urls.txt"
EOF

chmod +x ~/get_unifi_streams.sh

# 6. Create scripts for displaying camera feeds
cat > ~/display_camera.sh << 'EOF'
#!/bin/bash

# Function to play a single camera stream
play_camera() {
    local rtsp_url="$1"
    local duration="$2"
    
    echo "Playing stream: $rtsp_url"
    timeout "$duration" omxplayer --no-osd --no-keys --aspect-mode fill "$rtsp_url"
    return $?
}

# Check if URL is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <rtsp_url> [duration_in_seconds]"
    exit 1
fi

RTSP_URL="$1"
DURATION="${2:-300}"  # Default 5 minutes if not specified

play_camera "$RTSP_URL" "$DURATION"
EOF

chmod +x ~/display_camera.sh

# 7. Create a script to cycle through cameras
cat > ~/cycle_cameras.sh << 'EOF'
#!/bin/bash

# Configuration
ROTATION_INTERVAL=60  # Seconds to display each camera
RETRY_INTERVAL=10     # Seconds to wait before retrying on failure

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if the RTSP URLs file exists
if [ ! -f ~/rtsp_urls.txt ]; then
    log "RTSP URLs file not found. Please run get_unifi_streams.sh first."
    exit 1
fi

# Extract RTSP URLs from the file
URLS=()
while read -r line; do
    # Skip comments and empty lines
    if [[ ! "$line" =~ ^# ]] && [ ! -z "$line" ]; then
        URLS+=("$line")
    fi
done < ~/rtsp_urls.txt

# If no URLs found, exit
if [ ${#URLS[@]} -eq 0 ]; then
    log "No RTSP URLs found in the file."
    exit 1
fi

log "Starting camera rotation with ${#URLS[@]} cameras"

# Main loop to cycle through cameras
while true; do
    for url in "${URLS[@]}"; do
        log "Displaying next camera"
        
        # Start displaying the camera with a timeout
        ~/display_camera.sh "$url" "$ROTATION_INTERVAL"
        
        # If the player failed, wait a bit before trying the next camera
        if [ $? -ne 0 ]; then
            log "Error displaying camera. Retrying in $RETRY_INTERVAL seconds..."
            sleep "$RETRY_INTERVAL"
        fi
    done
done
EOF

chmod +x ~/cycle_cameras.sh

# 8. Create a service to auto-start the camera cycle
cat > /tmp/unifi-viewer.service << 'EOF'
[Unit]
Description=UniFi Camera Viewer using OMXPlayer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/cycle_cameras.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/unifi-viewer.service /etc/systemd/system/
sudo systemctl enable unifi-viewer.service

# 9. Create a setup script to configure UniFi connection settings
cat > ~/setup_unifi.sh << 'EOF'
#!/bin/bash

# Clear the terminal
clear

echo "UniFi Camera Viewer Setup"
echo "========================="
echo ""
echo "This script will help you set up your UniFi connection."
echo ""

# Get UniFi connection details
read -p "Enter your UniFi host or IP address: " UNIFI_HOST
read -p "Enter your UniFi port (default: 443): " UNIFI_PORT
UNIFI_PORT=${UNIFI_PORT:-443}
read -p "Enter your UniFi username: " UNIFI_USERNAME
read -sp "Enter your UniFi password: " UNIFI_PASSWORD
echo ""

# Update the get_unifi_streams.sh script with the provided details
sed -i "s/YOUR_UNIFI_HOST_OR_IP/$UNIFI_HOST/g" ~/get_unifi_streams.sh
sed -i "s/YOUR_UNIFI_USERNAME/$UNIFI_USERNAME/g" ~/get_unifi_streams.sh
sed -i "s/YOUR_UNIFI_PASSWORD/$UNIFI_PASSWORD/g" ~/get_unifi_streams.sh

echo ""
echo "Configuration updated!"
echo ""
echo "Would you like to retrieve camera streams now? (y/n)"
read RETRIEVE_NOW

if [[ $RETRIEVE_NOW == "y" || $RETRIEVE_NOW == "Y" ]]; then
    ~/get_unifi_streams.sh
    
    echo ""
    echo "Camera streams retrieved!"
    echo ""
    echo "Would you like to start viewing cameras now? (y/n)"
    read START_NOW
    
    if [[ $START_NOW == "y" || $START_NOW == "Y" ]]; then
        ~/cycle_cameras.sh
    else
        echo "You can start viewing cameras later by running: ~/cycle_cameras.sh"
    fi
else
    echo "You can retrieve camera streams later by running: ~/get_unifi_streams.sh"
fi
EOF

chmod +x ~/setup_unifi.sh

# 10. Create a watchdog script to monitor and restart if needed
cat > ~/watchdog.sh << 'EOF'
#!/bin/bash

# Configuration
CHECK_INTERVAL=60  # Check every minute

while true; do
    # Check if the cycle_cameras.sh script is running
    if ! pgrep -f "cycle_cameras.sh" > /dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Camera viewer not running. Restarting..."
        ~/cycle_cameras.sh &
    fi
    
    # Check memory usage
    FREE_MEM=$(free -m | grep Mem | awk '{print $4}')
    if [ $FREE_MEM -lt 50 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Low memory ($FREE_MEM MB). Killing OMXPlayer processes..."
        killall omxplayer.bin
        sleep 5
    fi
    
    sleep $CHECK_INTERVAL
done
EOF

chmod +x ~/watchdog.sh

# Add watchdog to crontab
(crontab -l 2>/dev/null; echo "@reboot ~/watchdog.sh &") | crontab -

# 11. Create a status checking script
cat > ~/check_status.sh << 'EOF'
#!/bin/bash

echo "UniFi Camera Viewer Status"
echo "=========================="
echo ""

# Check if configuration is set up
if grep -q "YOUR_UNIFI_HOST_OR_IP" ~/get_unifi_streams.sh; then
    echo "❌ Configuration: Not set up"
else
    echo "✅ Configuration: Set up"
fi

# Check if camera list exists
if [ -f ~/camera_list.txt ] && [ -s ~/camera_list.txt ]; then
    echo "✅ Camera list: Found ($(wc -l < ~/camera_list.txt) cameras)"
else
    echo "❌ Camera list: Not found"
fi

# Check if RTSP URLs exist
if [ -f ~/rtsp_urls.txt ] && [ -s ~/rtsp_urls.txt ]; then
    echo "✅ RTSP URLs: Found"
else
    echo "❌ RTSP URLs: Not found"
fi

# Check if the viewer is running
if pgrep -f "cycle_cameras.sh" > /dev/null; then
    echo "✅ Camera viewer: Running"
else
    echo "❌ Camera viewer: Not running"
fi

# Check if watchdog is running
if pgrep -f "watchdog.sh" > /dev/null; then
    echo "✅ Watchdog: Running"
else
    echo "❌ Watchdog: Not running"
fi

# Check memory usage
FREE_MEM=$(free -m | grep Mem | awk '{print $4}')
TOTAL_MEM=$(free -m | grep Mem | awk '{print $2}')
echo ""
echo "System status:"
echo "- Memory: $FREE_MEM MB free of $TOTAL_MEM MB"
echo "- CPU load: $(uptime | awk -F'load average: ' '{print $2}')"
echo "- OMXPlayer processes: $(pgrep -c omxplayer.bin || echo 0)"
EOF

chmod +x ~/check_status.sh

# 12. Final instructions
cat > ~/README.txt << 'EOF'
UniFi Camera Viewer - OMXPlayer Edition
======================================

Setup Instructions:
1. Run the setup script first:
   ./setup_unifi.sh

2. After setup, camera streams will be retrieved and saved.

3. The system will automatically start the camera viewer on boot.

Useful Commands:
- Check status: ./check_status.sh
- Manually retrieve camera streams: ./get_unifi_streams.sh
- Manually start camera viewer: ./cycle_cameras.sh
- Edit camera rotation interval: nano ~/cycle_cameras.sh (change ROTATION_INTERVAL)

Troubleshooting:
- If no video appears, check your UniFi credentials and connection
- If video is choppy, try a wired network connection
- For more logs, check: journalctl -u unifi-viewer.service
EOF

# Output message
echo "UniFi Camera Viewer (OMXPlayer) setup complete!"
echo ""
echo "To finalize setup:"
echo "1. Run the setup script: ./setup_unifi.sh"
echo "2. Enter your UniFi credentials when prompted"
echo "3. Check README.txt for more information"
echo ""
echo "The system will need to reboot to start the service. Reboot now? (y/n)"
read REBOOT_NOW

if [[ $REBOOT_NOW == "y" || $REBOOT_NOW == "Y" ]]; then
    sudo reboot
else
    echo "You can reboot later with: sudo reboot"
fi
