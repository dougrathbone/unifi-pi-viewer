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
sudo apt install -y omxplayer ffmpeg jq curl sed grep

# 5. Create an improved script to retrieve UniFi RTSP URLs with multiple auth methods
cat > ~/get_unifi_streams.sh << 'EOF'
#!/bin/bash
# Improved UniFi Protect Streams Script with Multiple Authentication Methods

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# UniFi Protect connection settings
UNIFI_HOST="YOUR_UNIFI_HOST_OR_IP"
UNIFI_PORT="443"
UNIFI_USERNAME="YOUR_UNIFI_USERNAME"
UNIFI_PASSWORD="YOUR_UNIFI_PASSWORD"

# Function to display messages with timestamp
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting UniFi Protect stream retrieval..."
log "${YELLOW}Trying multiple authentication methods...${NC}"

# METHOD 1: Cookie-based authentication (common in newer UniFi OS)
log "${YELLOW}Method 1: Trying Cookie-based authentication...${NC}"

# Create temp files for headers and response
HEADERS_FILE="/tmp/unifi_headers.txt"
RESPONSE_FILE="/tmp/unifi_response.json"

# Make the login request and save both headers and response
curl -s -k -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\"}" \
  -D "$HEADERS_FILE" \
  "https://$UNIFI_HOST:$UNIFI_PORT/api/auth/login" > "$RESPONSE_FILE"

# Check if we got a TOKEN cookie
if grep -q "TOKEN=" "$HEADERS_FILE" || grep -q "set-cookie: TOKEN" "$HEADERS_FILE"; then
    log "${GREEN}Cookie-based authentication successful!${NC}"
    
    # Extract token cookie and CSRF token
    TOKEN_COOKIE=$(grep -i "set-cookie: TOKEN=" "$HEADERS_FILE" | head -1 | sed -E 's/.*TOKEN=([^;]+);.*/\1/')
    CSRF_TOKEN=$(grep -i "x-csrf-token:" "$HEADERS_FILE" | cut -d' ' -f2 | tr -d '\r')
    
    log "${GREEN}Got authentication tokens${NC}"
    
    # Now try to access different endpoints to find cameras
    POTENTIAL_ENDPOINTS=(
        "/proxy/protect/api/bootstrap"
        "/proxy/protect/api/cameras"
        "/api/bootstrap"
        "/api/cameras"
        "/proxy/network/api/s/default/stat/device"
        "/api/devices"
    )
    
    # Try each endpoint
    for ENDPOINT in "${POTENTIAL_ENDPOINTS[@]}"; do
        log "${YELLOW}Trying to get cameras from $ENDPOINT...${NC}"
        
        CAMERA_RESPONSE=$(curl -s -k -X GET \
            -H "Content-Type: application/json" \
            -H "X-CSRF-Token: $CSRF_TOKEN" \
            -H "Cookie: TOKEN=$TOKEN_COOKIE" \
            "https://$UNIFI_HOST:$UNIFI_PORT$ENDPOINT")
        
        # Save response for debugging
        echo "$CAMERA_RESPONSE" > "/tmp/endpoint_${ENDPOINT//\//_}.json"
        
        # Check for camera data signatures
        if [[ "$CAMERA_RESPONSE" == *"\"cameras\":"* ]] || [[ "$CAMERA_RESPONSE" == *"\"deviceId\":"* ]] || [[ "$CAMERA_RESPONSE" == *"\"mac\":"* ]]; then
            log "${GREEN}Found potential camera data at $ENDPOINT${NC}"
            
            # If cameras are in a nested object, extract them
            if [[ "$CAMERA_RESPONSE" == *"\"cameras\":"* ]]; then
                echo "$CAMERA_RESPONSE" | sed -n 's/.*"cameras":\([^\]*\])\).*/\1/p' > "/tmp/camera_list.json"
            else
                echo "$CAMERA_RESPONSE" > "/tmp/camera_list.json"
            fi
            
            # Extract camera details directly using stream URLs if available
            if [[ "$CAMERA_RESPONSE" == *"\"rtspUris\":"* ]] || [[ "$CAMERA_RESPONSE" == *"\"rtspUrl\":"* ]]; then
                log "${GREEN}Direct RTSP URLs found in response!${NC}"
                # Extract RTSP URLs directly if they exist
                echo "$CAMERA_RESPONSE" | grep -o '"rtspUris":\[.*\]' | grep -o 'rtsp://[^"]*' > ~/rtsp_urls.txt
                
                if [ -s ~/rtsp_urls.txt ]; then
                    log "${GREEN}RTSP URLs extracted and saved to ~/rtsp_urls.txt${NC}"
                    exit 0
                fi
            fi
            
            # Try to extract camera IDs and create RTSP URLs
            log "${YELLOW}Extracting camera IDs to build RTSP URLs...${NC}"
            
            # Look for different ID patterns
            PATTERNS=(
                '"id":"([^"]*)"'
                '"deviceId":"([^"]*)"'
                '"mac":"([^"]*)"'
                '"_id":"([^"]*)"'
            )
            
            NAME_PATTERNS=(
                '"name":"([^"]*)"'
                '"model":"([^"]*)"'
                '"type":"([^"]*)"'
                '"deviceName":"([^"]*)"'
            )
            
            # Try to extract using all patterns
            for i in "${!PATTERNS[@]}"; do
                ID_PATTERN=${PATTERNS[$i]}
                NAME_PATTERN=${NAME_PATTERNS[$i]}
                
                log "${YELLOW}Trying to extract with pattern: $ID_PATTERN${NC}"
                
                # Use grep -o to extract matching patterns, then sed to extract the capture group
                CAMERA_IDS=$(grep -o "$ID_PATTERN" "/tmp/camera_list.json" | sed -E "s/$ID_PATTERN/\1/g")
                
                if [ -n "$CAMERA_IDS" ]; then
                    log "${GREEN}Found camera IDs with pattern: $ID_PATTERN${NC}"
                    
                    # Extract names if possible
                    CAMERA_NAMES=$(grep -o "$NAME_PATTERN" "/tmp/camera_list.json" | sed -E "s/$NAME_PATTERN/\1/g")
                    
                    # If we have names, pair them with IDs
                    if [ -n "$CAMERA_NAMES" ]; then
                        paste <(echo "$CAMERA_NAMES") <(echo "$CAMERA_IDS") | while read -r name id; do
                            echo "# $name"
                            echo "rtsp://$UNIFI_USERNAME:$UNIFI_PASSWORD@$UNIFI_HOST:7447/$id"
                            echo ""
                        done > ~/rtsp_urls.txt
                    else
                        # Just use IDs if no names
                        echo "$CAMERA_IDS" | while read -r id; do
                            echo "# Camera with ID: $id"
                            echo "rtsp://$UNIFI_USERNAME:$UNIFI_PASSWORD@$UNIFI_HOST:7447/$id"
                            echo ""
                        done > ~/rtsp_urls.txt
                    fi
                    
                    log "${GREEN}RTSP URLs saved to ~/rtsp_urls.txt${NC}"
                    exit 0
                fi
            done
        fi
    done
    
    # If we get here but authenticated successfully, we'll try method 2 anyway
    log "${YELLOW}Authenticated successfully, but couldn't extract camera data. Trying alternative method...${NC}"
fi

# METHOD 2: Modern UniFi Protect API with Bearer token
log "${YELLOW}Method 2: Trying modern UniFi Protect API with Bearer token...${NC}"
RESPONSE=$(curl -s -k -X POST -H "Content-Type: application/json" \
    -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\"}" \
    "https://$UNIFI_HOST:$UNIFI_PORT/api/auth/login")

# Extract authentication token
TOKEN=$(echo $RESPONSE | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
if [ -z "$TOKEN" ]; then
    TOKEN=$(echo $RESPONSE | grep -o '"Authorization":"[^"]*"' | cut -d'"' -f4)
fi

# Try to get cameras with token if available
if [ -n "$TOKEN" ]; then
    log "${GREEN}Authentication successful with Bearer token!${NC}"
    
    # Try different camera endpoints
    API_ENDPOINTS=(
        "/api/cameras"
        "/proxy/protect/api/cameras"
        "/api/bootstrap"
        "/proxy/protect/api/bootstrap"
    )
    
    for ENDPOINT in "${API_ENDPOINTS[@]}"; do
        log "Trying to get cameras from $ENDPOINT..."
        CAMERAS=$(curl -s -k -X GET -H "Content-Type: application/json" \
            -H "Authorization: Bearer $TOKEN" \
            "https://$UNIFI_HOST:$UNIFI_PORT$ENDPOINT")
        
        # Check if we got valid camera data
        if [[ "$CAMERAS" == *"id"* && "$CAMERAS" == *"name"* ]]; then
            log "${GREEN}Success! Got camera data from $ENDPOINT${NC}"
            
            # Parse depending on the API format
            if [[ "$ENDPOINT" == *"bootstrap"* ]]; then
                echo $CAMERAS | grep -o '"cameras":\[.*\]' | sed 's/"cameras"://g' > /tmp/camera_data.json
            else
                echo $CAMERAS > /tmp/camera_data.json
            fi
            
            # Extract camera IDs and names
            CAMERA_DATA=$(cat /tmp/camera_data.json)
            echo $CAMERA_DATA | grep -o '"id":"[^"]*","name":"[^"]*"' | while read -r line; do
                id=$(echo $line | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
                name=$(echo $line | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
                echo "# $name"
                echo "rtsp://$UNIFI_USERNAME:$UNIFI_PASSWORD@$UNIFI_HOST:7447/$id"
                echo ""
            done > ~/rtsp_urls.txt
            
            log "${GREEN}RTSP URLs saved to ~/rtsp_urls.txt${NC}"
            exit 0
        fi
    done
fi

# METHOD 3: Legacy UniFi Video API
log "${YELLOW}Method 3: Trying Legacy UniFi Video API...${NC}"

# Try the legacy API login
LEGACY_RESPONSE=$(curl -s -k -X POST \
    "https://$UNIFI_HOST:$UNIFI_PORT/api/login" \
    -d "username=$UNIFI_USERNAME&password=$UNIFI_PASSWORD")

if [[ "$LEGACY_RESPONSE" == *"api.auth.apiKey"* ]]; then
    log "${GREEN}Legacy authentication successful!${NC}"
    
    # Extract API key
    API_KEY=$(echo $LEGACY_RESPONSE | grep -o '"apiKey":"[^"]*"' | cut -d'"' -f4)
    
    # Get cameras using legacy API
    LEGACY_CAMERAS=$(curl -s -k -X GET \
        -H "Content-Type: application/json" \
        -H "Api-Key: $API_KEY" \
        "https://$UNIFI_HOST:$UNIFI_PORT/api/cameras")
    
    if [[ "$LEGACY_CAMERAS" == *"_id"* ]]; then
        log "${GREEN}Success! Got camera data from legacy API${NC}"
        
        # Extract camera IDs and names
        echo $LEGACY_CAMERAS | grep -o '"_id":"[^"]*","name":"[^"]*"' | while read -r line; do
            id=$(echo $line | grep -o '"_id":"[^"]*"' | cut -d'"' -f4)
            name=$(echo $line | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
            echo "# $name"
            echo "rtsp://$UNIFI_USERNAME:$UNIFI_PASSWORD@$UNIFI_HOST:7447/$id"
            echo ""
        done > ~/rtsp_urls.txt
        
        log "${GREEN}RTSP URLs saved to ~/rtsp_urls.txt${NC}"
        exit 0
    fi
fi

# FALLBACK: Manual entry if all methods failed
if [ ! -f ~/rtsp_urls.txt ] || [ ! -s ~/rtsp_urls.txt ]; then
    log "${YELLOW}All automated methods failed. Creating template for manual entry...${NC}"
    
    # Create a template file for manual editing
    cat > ~/rtsp_urls.txt << 'EOF'
# Camera 1
rtsp://YOUR_USERNAME:YOUR_PASSWORD@YOUR_HOST:7447/CAMERA_ID_1

# Camera 2
rtsp://YOUR_USERNAME:YOUR_PASSWORD@YOUR_HOST:7447/CAMERA_ID_2

# Note: Replace YOUR_USERNAME, YOUR_PASSWORD, YOUR_HOST, and CAMERA_ID_x with your actual values
# You can find camera IDs in the UniFi Protect web interface
EOF
    
    # Update template with actual credentials
    sed -i "s/YOUR_USERNAME/$UNIFI_USERNAME/g" ~/rtsp_urls.txt
    sed -i "s/YOUR_PASSWORD/$UNIFI_PASSWORD/g" ~/rtsp_urls.txt
    sed -i "s/YOUR_HOST/$UNIFI_HOST/g" ~/rtsp_urls.txt
    
    log "${YELLOW}Template RTSP URLs saved to ~/rtsp_urls.txt${NC}"
    log "${YELLOW}Please edit the file and replace CAMERA_ID_x with your actual camera IDs${NC}"
    exit 1
fi

# Clean up temp files
rm -f "$HEADERS_FILE" "$RESPONSE_FILE" "/tmp/camera_list.json" "/tmp/camera_data.json" "/tmp/endpoint_"*
EOF

chmod +x ~/get_unifi_streams.sh

# 6. Create an improved script for displaying camera feeds
cat > ~/display_camera.sh << 'EOF'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to log with timestamp
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to play a single camera stream
play_camera() {
    local rtsp_url="$1"
    local duration="$2"
    
    log "Playing stream: $rtsp_url"
    
    # Kill any existing OMXPlayer instances
    killall omxplayer.bin >/dev/null 2>&1
    
    # Start OMXPlayer with the stream
    # --timeout: Connection timeout in seconds
    # --live: Decrease latency for live streams
    # --no-osd: Don't show on-screen display
    # --no-keys: Disable keyboard controls
    # --aspect-mode fill: Fill the screen with the video
    timeout "$duration" omxplayer --timeout 10 --live --no-osd --no-keys --aspect-mode fill "$rtsp_url" >/dev/null 2>&1
    
    return $?
}

# Check if URL is provided
if [ -z "$1" ]; then
    log "${RED}Error: No RTSP URL provided${NC}"
    log "Usage: $0 <rtsp_url> [duration_in_seconds]"
    exit 1
fi

RTSP_URL="$1"
DURATION="${2:-300}"  # Default 5 minutes if not specified

play_camera "$RTSP_URL" "$DURATION"
EOF

chmod +x ~/display_camera.sh

# 7. Create an improved script to cycle through cameras
cat > ~/cycle_cameras.sh << 'EOF'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
RTSP_URLS_FILE=~/rtsp_urls.txt
ROTATION_INTERVAL=60  # Seconds to display each camera
RETRY_INTERVAL=10     # Seconds to wait before retrying on failure
LOG_FILE=~/camera_cycle.log

# Function to log with timestamp
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting camera cycle script..."

# Check if the RTSP URLs file exists
if [ ! -f "$RTSP_URLS_FILE" ]; then
    log "${RED}Error: RTSP URLs file not found at $RTSP_URLS_FILE${NC}"
    log "Please run get_unifi_streams.sh first to generate this file"
    exit 1
fi

# Extract RTSP URLs from the file
URLS=()
while read -r line; do
    # Skip comments and empty lines
    if [[ "$line" =~ ^rtsp:// ]]; then
        URLS+=("$line")
    fi
done < "$RTSP_URLS_FILE"

# Check if we found any URLs
if [ ${#URLS[@]} -eq 0 ]; then
    log "${RED}Error: No RTSP URLs found in $RTSP_URLS_FILE${NC}"
    log "Make sure your file contains lines starting with rtsp://"
    exit 1
fi

log "${GREEN}Found ${#URLS[@]} cameras to display${NC}"

# Main loop to cycle through cameras
while true; do
    for url in "${URLS[@]}"; do
        log "Displaying next camera"
        
        # Start displaying the camera with a timeout
        ~/display_camera.sh "$url" "$ROTATION_INTERVAL"
        
        # If the player failed, wait a bit before trying the next camera
        if [ $? -ne 0 ]; then
            log "${RED}Error displaying camera. Retrying in $RETRY_INTERVAL seconds...${NC}"
            sleep "$RETRY_INTERVAL"
        fi
    done
    
    # Small pause between cycles
    sleep 1
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

# 9. Create an improved setup script to configure UniFi connection settings
cat > ~/setup_unifi.sh << 'EOF'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Clear the terminal
clear

echo -e "${BLUE}UniFi Camera Viewer Setup${NC}"
echo -e "${BLUE}=========================${NC}"
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
# Use different delimiter for sed to avoid issues with special characters in password
sed -i "s|YOUR_UNIFI_HOST_OR_IP|$UNIFI_HOST|g" ~/get_unifi_streams.sh
sed -i "s|YOUR_UNIFI_USERNAME|$UNIFI_USERNAME|g" ~/get_unifi_streams.sh
sed -i "s|YOUR_UNIFI_PASSWORD|$UNIFI_PASSWORD|g" ~/get_unifi_streams.sh

echo ""
echo -e "${GREEN}Configuration updated!${NC}"
echo ""
echo "Would you like to retrieve camera streams now? (y/n)"
read RETRIEVE_NOW

if [[ $RETRIEVE_NOW == "y" || $RETRIEVE_NOW == "Y" ]]; then
    echo -e "${YELLOW}Retrieving camera streams...${NC}"
    ~/get_unifi_streams.sh
    
    # Check if the retrieval was successful
    if [ $? -eq 0 ] && [ -f ~/rtsp_urls.txt ] && [ -s ~/rtsp_urls.txt ]; then
        echo ""
        echo -e "${GREEN}Camera streams retrieved successfully!${NC}"
        
        # Count the number of cameras found
        CAMERA_COUNT=$(grep -c "^rtsp://" ~/rtsp_urls.txt)
        echo -e "${GREEN}Found $CAMERA_COUNT cameras.${NC}"
        
        echo ""
        echo "Would you like to start viewing cameras now? (y/n)"
        read START_NOW
        
        if [[ $START_NOW == "y" || $START_NOW == "Y" ]]; then
            echo -e "${YELLOW}Starting camera viewer...${NC}"
            ~/cycle_cameras.sh
        else
            echo "You can start viewing cameras later by running: ~/cycle_cameras.sh"
        fi
    else
        echo ""
        echo -e "${RED}Failed to retrieve camera streams automatically.${NC}"
        echo -e "${YELLOW}You may need to edit ~/rtsp_urls.txt manually.${NC}"
        echo "Please check the template file created and replace CAMERA_ID values with your actual camera IDs."
    fi
else
    echo "You can retrieve camera streams later by running: ~/get_unifi_streams.sh"
fi
EOF

chmod +x ~/setup_unifi.sh

# 10. Create an improved watchdog script
cat > ~/watchdog.sh << 'EOF'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
CHECK_INTERVAL=60  # Check every minute
LOG_FILE=~/watchdog.log
MEMORY_THRESHOLD=50  # MB

# Function to log with timestamp
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting camera viewer watchdog..."

while true; do
    # Check if the cycle_cameras.sh script is running
    if ! pgrep -f "cycle_cameras.sh" > /dev/null; then
        log "${RED}Camera viewer not running. Restarting...${NC}"
        ~/cycle_cameras.sh >> ~/camera_cycle.log 2>&1 &
        sleep 5
        
        # Verify it started
        if pgrep -f "cycle_cameras.sh" > /dev/null; then
            log "${GREEN}Camera viewer restarted successfully.${NC}"
        else
            log "${RED}Failed to restart camera viewer!${NC}"
        fi
    fi
    
    # Check for zombie OMXPlayer processes
    ZOMBIE_COUNT=$(ps aux | grep defunct | grep omxplayer | wc -l)
    if [ $ZOMBIE_COUNT -gt 0 ]; then
        log "${YELLOW}Found $ZOMBIE_COUNT zombie OMXPlayer processes. Cleaning up...${NC}"
        killall -9 omxplayer.bin >/dev/null 2>&1
    fi
    
    # Check memory usage
    FREE_MEM=$(free -m | grep Mem | awk '{print $4}')
    if [ $FREE_MEM -lt $MEMORY_THRESHOLD ]; then
        log "${RED}Low memory ($FREE_MEM MB). Killing OMXPlayer processes...${NC}"
        killall omxplayer.bin >/dev/null 2>&1
        sleep 5
    fi
    
    # Check system temperature
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
        TEMP_C=$((TEMP/1000))
        
        # If temperature is above 80°C, log a warning
        if [ $TEMP_C -gt 80 ]; then
            log "${RED}WARNING: System temperature is $TEMP_C°C. This is too hot!${NC}"
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
EOF

chmod +x ~/watchdog.sh

# Add watchdog to crontab
(crontab -l 2>/dev/null; echo "@reboot ~/watchdog.sh &") | crontab -

# 11. Create an improved status checking script
cat > ~/check_status.sh << 'EOF'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}UniFi Camera Viewer Status${NC}"
echo -e "${BLUE}==========================${NC}"
echo ""

# Check if configuration is set up
if grep -q "YOUR_UNIFI_HOST_OR_IP" ~/get_unifi_streams.sh; then
    echo -e "${RED}❌ Configuration: Not set up${NC}"
else
    echo -e "${GREEN}✅ Configuration: Set up${NC}"
    UNIFI_HOST=$(grep "UNIFI_HOST=" ~/get_unifi_streams.sh | head -1 | cut -d'"' -f2)
    UNIFI_USERNAME=$(grep "UNIFI_USERNAME=" ~/get_unifi_streams.sh | head -1 | cut -d'"' -f2)
    echo "   Host: $UNIFI_HOST"
    echo "   Username: $UNIFI_USERNAME"
fi

# Check if RTSP URLs exist
if [ -f ~/rtsp_urls.txt ] && [ -s ~/rtsp_urls.txt ]; then
    CAMERA_COUNT=$(grep -c "^rtsp://" ~/rtsp_urls.txt)
    echo -e "${GREEN}✅ RTSP URLs: Found ($CAMERA_COUNT cameras)${NC}"
else
    echo -e "${RED}❌ RTSP URLs: Not found${NC}"
fi

# Test network connectivity to UniFi host
if [ -n "$UNIFI_HOST" ]; then
    echo ""
    echo "Testing connection to UniFi host..."
    if ping -c 1 -W 2 $UNIFI_HOST > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Network: UniFi host is reachable${NC}"
    else
        echo -e "${RED}❌ Network: Cannot reach UniFi host${NC}"
    fi
fi

# Check if the viewer is running
if pgrep -f "cycle_cameras.sh" > /dev/null; then
    echo -e "${GREEN}✅ Camera viewer: Running${NC}"
    RUNTIME=$(ps -o etime= -p $(pgrep -f "cycle_cameras.sh" | head -1))
    echo "   Running for: $RUNTIME"
else
    echo -e "${RED}❌ Camera viewer: Not running${NC}"
fi

# Check if watchdog is running
if pgrep -f "watchdog.sh" > /dev/null; then
    echo -e "${GREEN}✅ Watchdog: Running${NC}"
else
    echo -e "${RED}❌ Watchdog: Not running${NC}"
fi

# Check for OMXPlayer processes
OMXPLAYER_COUNT=$(pgrep -c omxplayer.bin || echo 0)
if [ $OMXPLAYER_COUNT -gt 0 ]; then
    echo -e "${GREEN}✅ OMXPlayer: $OMXPLAYER_COUNT instance(s) running${NC}"
else
    echo -e "${YELLOW}⚠️ OMXPlayer: No instances running${NC}"
fi

# Check system status
echo ""
echo -e "${BLUE}System status:${NC}"
# Memory usage
FREE_MEM=$(free -m | grep Mem | awk '{print $4}')
TOTAL_MEM=$(free -m | grep Mem | awk '{print $2}')
MEM_PERCENT=$((100 - FREE_MEM * 100 / TOTAL_MEM))

if [ $MEM_PERCENT -gt 85 ]; then
    echo -e "${RED}- Memory: $FREE_MEM MB free of $TOTAL_MEM MB ($MEM_PERCENT% used)${NC}"
elif [ $MEM_PERCENT -gt 70 ]; then
    echo -e "${YELLOW}- Memory: $FREE_MEM MB free of $TOTAL_MEM MB ($MEM_PERCENT% used)${NC}"
else
    echo -e "${GREEN}- Memory: $FREE_MEM MB free of $TOTAL_MEM MB ($MEM_PERCENT% used)${NC}"
fi

# CPU temperature
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$((TEMP/1000))
    
    if [ $TEMP_C -gt 80 ]; then
        echo -e "${RED}- CPU temperature: $TEMP_C°C (TOO HOT!)${NC}"
    elif [ $TEMP_C -gt 70 ]; then
        echo -e "${YELLOW}- CPU temperature: $TEMP_C°C (HOT)${NC}"
    else
        echo -e "${GREEN}- CPU temperature: $TEMP_C°C${NC}"
    fi
fi

# CPU load
LOAD=$(uptime | awk -F'load average: ' '{print $2}')
echo "- CPU load: $LOAD"

# Network status
ETH0_STATUS=$(cat /sys/class/net/eth0/operstate 2>/dev/null || echo "unavailable")
WLAN0_STATUS=$(cat /sys/class/net/wlan0/operstate 2>/dev/null || echo "unavailable")

if [ "$ETH0_STATUS" = "up" ]; then
    echo -e "${GREEN}- Ethernet: Connected${NC}"
elif [ "$ETH0_STATUS" = "down" ]; then
    echo -e "${RED}- Ethernet: Disconnected${NC}"
else
    echo "- Ethernet: $ETH0_STATUS"
fi

if [ "$WLAN0_STATUS" = "up" ]; then
    WIFI_QUALITY=$(iwconfig wlan0 2>/dev/null | grep "Link Quality" | awk '{print $2}' | cut -d'=' -f2)
    WIFI_SIGNAL=$(iwconfig wlan0 2>/dev/null | grep "Signal level" | awk '{print $4}' | cut -d'=' -f2)
    echo -e "${GREEN}- WiFi: Connected (Quality: $WIFI_QUALITY, Signal: $WIFI_SIGNAL dBm)${NC}"
elif [ "$WLAN0_STATUS" = "down" ]; then
    echo -e "${RED}- WiFi: Disconnected${NC}"
else
    echo "- WiFi: $WLAN0_STATUS"
fi

# Check for any errors in logs
RECENT_ERRORS=$(grep -i "error\|failed\|warning" ~/camera_cycle.log 2>/dev/null | tail -5)
if [ -n "$RECENT_ERRORS" ]; then
    echo ""
    echo -e "${YELLOW}Recent errors/warnings:${NC}"
    echo "$RECENT_ERRORS"
fi

echo ""
echo -e "${BLUE}Tip: Run 'journalctl -u unifi-viewer.service' to see complete system logs${NC}"
EOF

chmod +x ~/check_status.sh

# 12. Create improved README
cat > ~/README.txt << 'EOF'
UniFi Camera Viewer - OMXPlayer Edition
======================================

This setup uses OMXPlayer to display UniFi Protect camera feeds on your Raspberry Pi.
It supports multiple authentication methods to work with different UniFi Protect versions.

Setup Instructions:
1. Run the setup script first:
   ./setup_unifi.sh

2. Enter your UniFi credentials when prompted.

3. The system will automatically retrieve your camera streams and save them.

4. After setup, the viewer will start automatically on boot.

Useful Commands:
- Check status: ./check_status.sh
- Manually retrieve camera streams: ./get_unifi_streams.sh
- Manually start camera viewer: ./cycle_cameras.sh
- Change camera rotation time: Edit ROTATION_INTERVAL in ~/cycle_cameras.sh

Troubleshooting:
- If the viewer fails to authenticate, it will create a template file that you can edit manually
- If video is choppy, try using a wired network connection instead of WiFi
- Check logs with: tail -f ~/camera_cycle.log
- For system service logs: journalctl -u unifi-viewer.service
- If your Pi gets too hot, consider adding a heatsink or fan

Manual RTSP URL format:
rtsp://USERNAME:PASSWORD@HOST:7447/CAMERA_ID

Finding Camera IDs:
1. Log into your UniFi Protect interface
2. Go to Devices > [Camera Name] > Settings > Advanced
3. Look for the Device ID or MAC address
4. Or enable RTSP in camera settings and copy the provided URL
EOF

# 13. Output final message
echo -e "\e[1;32mUniFi Camera Viewer (OMXPlayer) setup complete!\e[0m"
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
