#!/bin/bash
# UniFi Authentication Troubleshooting Script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display messages with timestamp
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Print header
echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}    UniFi Protect Authentication Tester     ${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# Prompt for credentials
read -p "Enter UniFi Protect host/IP: " UNIFI_HOST
read -p "Enter UniFi Protect port [443]: " UNIFI_PORT
UNIFI_PORT=${UNIFI_PORT:-443}
read -p "Enter UniFi username: " UNIFI_USERNAME
read -sp "Enter UniFi password: " UNIFI_PASSWORD
echo ""

# Verify credentials exist
if [ -z "$UNIFI_HOST" ] || [ -z "$UNIFI_USERNAME" ] || [ -z "$UNIFI_PASSWORD" ]; then
  log "${RED}Error: Missing credentials. All fields are required.${NC}"
  exit 1
fi

# First test - basic connectivity
log "${YELLOW}Testing basic connectivity to $UNIFI_HOST:$UNIFI_PORT...${NC}"
PING_RESULT=$(ping -c 1 $UNIFI_HOST 2>&1)
if [ $? -eq 0 ]; then
  log "${GREEN}Ping successful - host is reachable${NC}"
else
  log "${RED}Error: Unable to ping host. Check if the host is online.${NC}"
  echo "$PING_RESULT"
  log "${YELLOW}Note: Some networks may block ICMP ping. Continuing anyway...${NC}"
fi

# Test port connectivity
log "${YELLOW}Testing connection to port $UNIFI_PORT...${NC}"
PORT_TEST=$(timeout 5 bash -c "echo > /dev/tcp/$UNIFI_HOST/$UNIFI_PORT" 2>&1)
if [ $? -eq 0 ]; then
  log "${GREEN}Port $UNIFI_PORT is open and accessible${NC}"
else
  log "${RED}Error: Unable to connect to port $UNIFI_PORT. Check your firewall settings.${NC}"
  echo "$PORT_TEST"
fi

# Test API versions and endpoints
log "${YELLOW}Detecting UniFi Protect API version...${NC}"

# Create a temp dir to store responses
TEMP_DIR=$(mktemp -d)
RESPONSE_FILE="$TEMP_DIR/response.json"
HEADERS_FILE="$TEMP_DIR/headers.txt"

# Test UniFi Protect API version 1 endpoints
log "${YELLOW}Trying modern UniFi Protect API (v1)...${NC}"

# Set URL and output debug info
AUTH_URL="https://$UNIFI_HOST:$UNIFI_PORT/api/auth/login"
log "${BLUE}Endpoint: $AUTH_URL${NC}"

# Make authenticated request with verbose output
curl -s -k -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\"}" \
  -D "$HEADERS_FILE" \
  "$AUTH_URL" > "$RESPONSE_FILE" 2>&1

# Check for successful response and token
if grep -q "200 OK\|201 Created" "$HEADERS_FILE"; then
  log "${GREEN}Connected to the API successfully!${NC}"
  
  # Check for different token formats
  TOKEN=$(cat "$RESPONSE_FILE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
  if [ -z "$TOKEN" ]; then
    TOKEN=$(cat "$RESPONSE_FILE" | grep -o '"Authorization":"[^"]*"' | cut -d'"' -f4)
  fi
  
  if [ ! -z "$TOKEN" ]; then
    log "${GREEN}Authentication successful! Token received.${NC}"
    TOKEN_PREVIEW="${TOKEN:0:20}...${TOKEN: -10}"
    log "${BLUE}Token: $TOKEN_PREVIEW${NC}"
    
    # Test cameras endpoint
    log "${YELLOW}Testing camera access...${NC}"
    # Try different API endpoints
    ENDPOINTS=(
      "/api/cameras"
      "/api/bootstrap"
      "/proxy/protect/api/cameras"
      "/proxy/protect/api/bootstrap"
    )
    
    for ENDPOINT in "${ENDPOINTS[@]}"; do
      CAMERA_URL="https://$UNIFI_HOST:$UNIFI_PORT$ENDPOINT"
      log "${BLUE}Trying endpoint: $ENDPOINT${NC}"
      
      CAMERA_RESPONSE=$(curl -s -k -X GET \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        "$CAMERA_URL")
      
      # Check if response contains camera data
      if [[ "$CAMERA_RESPONSE" == *"id"* && "$CAMERA_RESPONSE" == *"name"* ]]; then
        log "${GREEN}Success! Cameras data retrieved from $ENDPOINT${NC}"
        echo ""
        log "${GREEN}This endpoint works: $ENDPOINT${NC}"
        log "${GREEN}Update your script to use this endpoint.${NC}"
        break
      else
        log "${RED}No camera data found at $ENDPOINT${NC}"
      fi
    done
  else
    log "${RED}Token not found in response. Authentication may have failed.${NC}"
    echo ""
    log "${YELLOW}Response headers:${NC}"
    cat "$HEADERS_FILE"
    echo ""
    log "${YELLOW}Response body (first 500 chars):${NC}"
    head -c 500 "$RESPONSE_FILE"
    echo ""
  fi
else
  log "${RED}Failed to connect to the API. Status code not 200/201.${NC}"
  echo ""
  log "${YELLOW}Response headers:${NC}"
  cat "$HEADERS_FILE"
  echo ""
  log "${YELLOW}Response body (first 500 chars):${NC}"
  head -c 500 "$RESPONSE_FILE"
  echo ""
fi

# Test UniFi Protect API version 2 endpoints
log "${YELLOW}Trying alternate UniFi OS API endpoints...${NC}"

# Test UniFi OS login
AUTH_URL="https://$UNIFI_HOST:$UNIFI_PORT/api/auth"
log "${BLUE}Endpoint: $AUTH_URL${NC}"

curl -s -k -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\",\"rememberMe\":true}" \
  -D "$HEADERS_FILE" \
  "$AUTH_URL" > "$RESPONSE_FILE" 2>&1

# Check if we got a cookie
if grep -q "unifises\|csrf" "$HEADERS_FILE"; then
  log "${GREEN}UniFi OS login successful! Session cookie received.${NC}"
  
  # Extract cookies
  CSRF_TOKEN=$(grep -i "X-CSRF-Token:" "$HEADERS_FILE" | cut -d' ' -f2 | tr -d '\r')
  COOKIE=$(grep -i "Set-Cookie:" "$HEADERS_FILE" | grep -i "unifises" | cut -d' ' -f2 | tr -d '\r')
  
  if [ ! -z "$CSRF_TOKEN" ] && [ ! -z "$COOKIE" ]; then
    log "${GREEN}Got session tokens.${NC}"
    log "${BLUE}X-CSRF-Token: ${CSRF_TOKEN:0:20}...${NC}"
    log "${BLUE}Cookie: ${COOKIE:0:20}...${NC}"
    
    # Test different API endpoints with cookie auth
    log "${YELLOW}Testing camera access with cookie authentication...${NC}"
    COOKIE_ENDPOINTS=(
      "/proxy/protect/api/bootstrap"
      "/proxy/network/api/s/default/stat/device"
      "/proxy/protect/api/nvr"
      "/api/users/self"
    )
    
    for ENDPOINT in "${COOKIE_ENDPOINTS[@]}"; do
      CAMERA_URL="https://$UNIFI_HOST:$UNIFI_PORT$ENDPOINT"
      log "${BLUE}Trying endpoint: $ENDPOINT${NC}"
      
      CAMERA_RESPONSE=$(curl -s -k -X GET \
        -H "Content-Type: application/json" \
        -H "X-CSRF-Token: $CSRF_TOKEN" \
        -H "Cookie: $COOKIE" \
        "$CAMERA_URL")
      
      # Check if response seems valid
      if [[ "$CAMERA_RESPONSE" != *"error"* && "$CAMERA_RESPONSE" != *"unauthorized"* ]]; then
        log "${GREEN}Success! Data retrieved from $ENDPOINT${NC}"
        echo ""
        log "${GREEN}This endpoint works with cookie auth: $ENDPOINT${NC}"
        log "${GREEN}Update your script to use cookie authentication with this endpoint.${NC}"
        log "${YELLOW}Use these headers:${NC}"
        log "${BLUE}X-CSRF-Token: $CSRF_TOKEN${NC}"
        log "${BLUE}Cookie: $COOKIE${NC}"
        break
      else
        log "${RED}No valid data found at $ENDPOINT${NC}"
      fi
    done
  else
    log "${RED}Cookie or CSRF token not found in response.${NC}"
    log "${YELLOW}Response headers:${NC}"
    cat "$HEADERS_FILE"
  fi
else
  log "${RED}UniFi OS login failed. No session cookie received.${NC}"
  log "${YELLOW}Response headers:${NC}"
  cat "$HEADERS_FILE"
  echo ""
  log "${YELLOW}Response body (first 500 chars):${NC}"
  head -c 500 "$RESPONSE_FILE"
  echo ""
fi

# Test RTSP access directly
log "${YELLOW}Testing direct RTSP access...${NC}"
log "${BLUE}Attempting to connect to RTSP on port 7447...${NC}"

# Test RTSP port connectivity
RTSP_PORT=7447
RTSP_TEST=$(timeout 5 bash -c "echo > /dev/tcp/$UNIFI_HOST/$RTSP_PORT" 2>&1)
if [ $? -eq 0 ]; then
  log "${GREEN}RTSP port 7447 is open and accessible${NC}"
  log "${YELLOW}Your UniFi Protect system appears to have RTSP enabled${NC}"
  log "${YELLOW}RTSP URLs should be in format: rtsp://$UNIFI_USERNAME:$UNIFI_PASSWORD@$UNIFI_HOST:7447/CAMERA_ID${NC}"
else
  log "${RED}Error: Unable to connect to RTSP port 7447.${NC}"
  log "${YELLOW}Possible reasons:${NC}"
  log "${YELLOW}- RTSP might not be enabled in UniFi Protect${NC}"
  log "${YELLOW}- Firewall might be blocking port 7447${NC}"
  log "${YELLOW}- UniFi device might be configured with a different RTSP port${NC}"
fi

# Clean up temp files
rm -rf "$TEMP_DIR"

echo ""
log "${BLUE}=============================================${NC}"
log "${BLUE}           Troubleshooting Summary           ${NC}"
log "${BLUE}=============================================${NC}"

# Print recommended next steps
echo ""
log "${YELLOW}Recommended next steps:${NC}"
log "1. Check if you're using the correct username and password"
log "2. Verify that your UniFi Protect version is compatible"
log "3. Make sure RTSP is enabled in your UniFi Protect settings"
log "4. Check that ports 443 and 7447 are not blocked by firewall"
log "5. Try using a UniFi local account instead of cloud SSO, if applicable"
log "6. Update the script with the correct API endpoint detected by this tool"

echo ""
log "${BLUE}For additional help, check the UniFi Protect documentation or community forums.${NC}"
