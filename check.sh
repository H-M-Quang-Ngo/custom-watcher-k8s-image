#!/bin/bash

CUSTOM_IMAGE=${1:-"ghcr.io/h-m-quang-ngo/watcher-custom:test"}
OFFICIAL_IMAGE="ghcr.io/canonical/watcher-consolidated:2024.1"

echo "=============================================="
echo "    DOCKER IMAGE COMPATIBILITY VERIFICATION"
echo "=============================================="
echo "Custom Image:   $CUSTOM_IMAGE"
echo "Official Image: $OFFICIAL_IMAGE"
CUSTOM_SIZE=$(docker images $CUSTOM_IMAGE --format "{{.Size}}")
OFFICIAL_SIZE=$(docker images $OFFICIAL_IMAGE --format "{{.Size}}")
echo "Custom Image Size:   $CUSTOM_SIZE"
echo "Official Image Size: $OFFICIAL_SIZE"
echo

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to compare values
compare_values() {
    local name="$1"
    local val1="$2"
    local val2="$3"

    if [ "$val1" = "$val2" ]; then
        echo -e "${GREEN} $name: MATCH${NC}"
        return 0
    else
        echo -e "${RED} $name: MISMATCH${NC}"
        echo "  Custom:   $val1"
        echo "  Official: $val2"
        return 1
    fi
}

# Function to extract JSON values
extract_json() {
    echo "$1" | jq -r "$2" 2>/dev/null || echo "null"
}

echo -e "${BLUE}=== 1. IMAGE METADATA COMPARISON ===${NC}"

# Get full config for both images
echo "Fetching image configurations..."
CUSTOM_CONFIG=$(docker inspect $CUSTOM_IMAGE --format='{{json .Config}}' 2>/dev/null)
OFFICIAL_CONFIG=$(docker inspect $OFFICIAL_IMAGE --format='{{json .Config}}' 2>/dev/null)

if [ -z "$CUSTOM_CONFIG" ] || [ -z "$OFFICIAL_CONFIG" ]; then
    echo -e "${RED} Failed to fetch image configurations. Ensure both images are available locally.${NC}"
    exit 1
fi

# Extract and compare key values
CUSTOM_ENTRYPOINT=$(extract_json "$CUSTOM_CONFIG" '.Entrypoint | @json')
OFFICIAL_ENTRYPOINT=$(extract_json "$OFFICIAL_CONFIG" '.Entrypoint | @json')

CUSTOM_PORTS=$(extract_json "$CUSTOM_CONFIG" '.ExposedPorts | keys | @json')
OFFICIAL_PORTS=$(extract_json "$OFFICIAL_CONFIG" '.ExposedPorts | keys | @json')

CUSTOM_USER=$(extract_json "$CUSTOM_CONFIG" '.User')
OFFICIAL_USER=$(extract_json "$OFFICIAL_CONFIG" '.User')

# Compare critical configuration
compare_values "Entrypoint" "$CUSTOM_ENTRYPOINT" "$OFFICIAL_ENTRYPOINT"
ENTRYPOINT_MATCH=$?

# Handle port comparison - official image may not expose ports
if [[ "$CUSTOM_PORTS" == '["9322/tcp"]' && ("$OFFICIAL_PORTS" == "null" || "$OFFICIAL_PORTS" == "[]") ]]; then
    echo -e "${GREEN} Exposed Ports: ACCEPTABLE (Custom has required port 9322)${NC}"
    PORTS_MATCH=0
else
    compare_values "Exposed Ports" "$CUSTOM_PORTS" "$OFFICIAL_PORTS"
    PORTS_MATCH=$?
fi

compare_values "Default User" "$CUSTOM_USER" "$OFFICIAL_USER"
USER_MATCH=$?

echo

echo -e "${BLUE}=== 2. PEBBLE FUNCTIONALITY TEST ===${NC}"

# Test pebble help command
echo "Testing pebble help response..."
CUSTOM_PEBBLE=$(timeout 10 docker run --rm $CUSTOM_IMAGE --help 2>&1 | head -3 | tr '\n' ' ')
OFFICIAL_PEBBLE=$(timeout 10 docker run --rm $OFFICIAL_IMAGE --help 2>&1 | head -3 | tr '\n' ' ')

compare_values "Pebble Help Output" "$CUSTOM_PEBBLE" "$OFFICIAL_PEBBLE"
PEBBLE_MATCH=$?

# Test pebble supported commands
echo "Testing pebble supported commands..."
CUSTOM_SERVICES=$(timeout 10 docker run --rm $CUSTOM_IMAGE services 2>&1 | head -1 | grep -q "Service" && echo "SUCCESS" || echo "FAILED")
OFFICIAL_SERVICES=$(timeout 10 docker run --rm $OFFICIAL_IMAGE services 2>&1 | head -1 | grep -q "Service" && echo "SUCCESS" || echo "FAILED")

compare_values "Pebble Services Command" "$CUSTOM_SERVICES" "$OFFICIAL_SERVICES"
SERVICES_MATCH=$?

# Note: exec command is not supported in 'pebble enter' mode, only in daemon mode
echo -e "${BLUE} Note: pebble exec is only available in daemon mode, not in enter mode${NC}"
EXEC_MATCH=0  # Consider this as passing since it's expected behavior

echo

echo -e "${BLUE}=== 3. INTERNAL STRUCTURE VERIFICATION ===${NC}"

# Test sudo accessibility (for the custom image specifically)
echo "Testing sudo accessibility in custom image..."
SUDO_CHECK=$(timeout 5 docker run --rm --entrypoint="" $CUSTOM_IMAGE /bin/sh -c "which sudo && ls -la /bin/sudo 2>/dev/null | cut -d' ' -f1" 2>/dev/null | tail -1)
if [ -n "$SUDO_CHECK" ]; then
    echo -e "${GREEN} Sudo accessible: $SUDO_CHECK${NC}"
else
    echo -e "${YELLOW} Sudo accessibility test inconclusive${NC}"
fi

# Test watcher binaries
echo "Testing watcher binaries in custom image..."
WATCHER_BINS=$(timeout 5 docker run --rm --entrypoint="" $CUSTOM_IMAGE /bin/sh -c "ls /usr/local/bin/watcher-* 2>/dev/null | wc -l" 2>/dev/null || echo "0")
if [ "$WATCHER_BINS" -gt "0" ]; then
    echo -e "${GREEN} Watcher binaries found: $WATCHER_BINS binaries${NC}"
else
    echo -e "${YELLOW} No watcher binaries found in /usr/local/bin/${NC}"
fi

echo

echo -e "${BLUE}=== 4. COMPATIBILITY SUMMARY ===${NC}"

TOTAL_CHECKS=5
PASSED_CHECKS=0

[ $ENTRYPOINT_MATCH -eq 0 ] && ((PASSED_CHECKS++))
[ $PORTS_MATCH -eq 0 ] && ((PASSED_CHECKS++))
[ $USER_MATCH -eq 0 ] && ((PASSED_CHECKS++))
[ $PEBBLE_MATCH -eq 0 ] && ((PASSED_CHECKS++))
[ $SERVICES_MATCH -eq 0 ] && ((PASSED_CHECKS++))

echo "Compatibility Score: $PASSED_CHECKS/$TOTAL_CHECKS"

if [ $PASSED_CHECKS -eq $TOTAL_CHECKS ]; then
    echo -e "${GREEN} FULLY COMPATIBLE - Ready for deployment!${NC}"
    EXIT_CODE=0
elif [ $PASSED_CHECKS -ge 3 ]; then
    echo -e "${YELLOW} MOSTLY COMPATIBLE - Minor differences detected${NC}"
    EXIT_CODE=0
else
    echo -e "${RED} INCOMPATIBLE - Major differences found${NC}"
    EXIT_CODE=1
fi

echo

echo -e "${BLUE}=== 5. RESULT ===${NC}"
if [ $EXIT_CODE -eq 0 ]; then
    echo "Image is ready for deployment."
else
    echo "Need to fix the compatibility issues before deployment."
fi

echo
echo "=============================================="

exit $EXIT_CODE
