#!/bin/bash

# Quick stress test script for rapid validation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}⚡ I2P Bridge Quick Stress Test${NC}"
echo -e "${CYAN}===============================${NC}"

# Check API key
if [ -z "$I2P_BRIDGE_API_KEY" ]; then
    echo -e "${RED}❌ Error: I2P_BRIDGE_API_KEY environment variable is required${NC}"
    echo -e "${YELLOW}💡 Set it with: export I2P_BRIDGE_API_KEY=your-api-key${NC}"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo -e "${BLUE}📦 Installing dependencies...${NC}"
    npm install
fi

# Quick validation tests
echo -e "\n${BLUE}🔍 Running quick validation tests...${NC}"

# Test 1: HTTP (light load)
echo -e "${YELLOW}📡 Testing HTTP browsing (5 users, 30s)...${NC}"
node http-stress-test.js --users=5 --duration=30 || {
    echo -e "${RED}❌ HTTP test failed${NC}"
    exit 1
}

# Test 2: IRC (minimal load) 
echo -e "\n${YELLOW}💬 Testing IRC connections (3 users, 45s)...${NC}"
node irc-stress-test.js --users=3 --duration=45 || {
    echo -e "${RED}❌ IRC test failed${NC}"
    exit 1
}

# Test 3: Upload (minimal load)
echo -e "\n${YELLOW}📤 Testing file uploads (2 users, 30s)...${NC}"
node upload-stress-test.js --users=2 --duration=30 || {
    echo -e "${RED}❌ Upload test failed${NC}"
    exit 1
}

echo -e "\n${GREEN}🎉 Quick stress test completed successfully!${NC}"
echo -e "${BLUE}💡 For comprehensive testing, run: ./run-all-tests.sh${NC}"
echo -e "${BLUE}📊 For real-time monitoring, run: npm run monitor${NC}"