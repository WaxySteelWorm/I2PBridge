#!/bin/bash

# I2P Bridge Comprehensive Stress Testing Script
# This script runs all stress tests in sequence with different load levels

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🎯 I2P Bridge Comprehensive Stress Testing${NC}"
echo -e "${CYAN}==========================================${NC}"

# Check if API key is set
if [ -z "$I2P_BRIDGE_API_KEY" ]; then
    echo -e "${RED}❌ Error: I2P_BRIDGE_API_KEY environment variable is required${NC}"
    echo -e "${YELLOW}💡 Set it with: export I2P_BRIDGE_API_KEY=your-api-key${NC}"
    exit 1
fi

echo -e "${GREEN}✅ API key configured${NC}"

# Check if node modules are installed
if [ ! -d "node_modules" ]; then
    echo -e "${BLUE}📦 Installing dependencies...${NC}"
    npm install
fi

# Create results directory
mkdir -p results
echo -e "${BLUE}📁 Results will be saved to: $(pwd)/results${NC}"

# Function to run a test with error handling
run_test() {
    local test_name="$1"
    local script="$2"
    local users="$3"
    local duration="$4"
    local description="$5"
    
    echo -e "\n${CYAN}🚀 Starting $test_name${NC}"
    echo -e "${BLUE}   Description: $description${NC}"
    echo -e "${BLUE}   Users: $users | Duration: ${duration}s${NC}"
    echo -e "${BLUE}   Command: node $script --users=$users --duration=$duration${NC}"
    
    if node "$script" --users="$users" --duration="$duration" 2>&1 | tee "results/${test_name}-$(date +%Y%m%d-%H%M%S).log"; then
        echo -e "${GREEN}✅ $test_name completed successfully${NC}"
        return 0
    else
        echo -e "${RED}❌ $test_name failed${NC}"
        return 1
    fi
}

# Test progression: Light -> Medium -> Heavy
echo -e "\n${YELLOW}📊 Test Progression Overview:${NC}"
echo -e "   1. Light Load Tests (baseline performance)"
echo -e "   2. Medium Load Tests (normal expected load)"
echo -e "   3. Heavy Load Tests (peak load scenarios)"

# Phase 1: Light Load Tests
echo -e "\n${CYAN}🌟 PHASE 1: LIGHT LOAD TESTS${NC}"
echo -e "${CYAN}============================${NC}"

run_test "light-http" "http-stress-test.js" 10 60 "Baseline HTTP browsing performance"
sleep 5

run_test "light-irc" "irc-stress-test.js" 5 60 "Baseline IRC connection performance" 
sleep 5

run_test "light-upload" "upload-stress-test.js" 3 60 "Baseline upload performance"
sleep 10

# Phase 2: Medium Load Tests  
echo -e "\n${CYAN}🔥 PHASE 2: MEDIUM LOAD TESTS${NC}"
echo -e "${CYAN}=============================${NC}"

run_test "medium-http" "http-stress-test.js" 25 120 "Normal expected HTTP load"
sleep 10

run_test "medium-irc" "irc-stress-test.js" 15 120 "Normal expected IRC load"
sleep 10

run_test "medium-upload" "upload-stress-test.js" 8 90 "Normal expected upload load"
sleep 15

# Phase 3: Heavy Load Tests
echo -e "\n${CYAN}💥 PHASE 3: HEAVY LOAD TESTS${NC}"
echo -e "${CYAN}============================${NC}"

run_test "heavy-http" "http-stress-test.js" 50 180 "Peak HTTP browsing load"
sleep 15

run_test "heavy-irc" "irc-stress-test.js" 25 180 "Peak IRC connection load"
sleep 15

run_test "heavy-upload" "upload-stress-test.js" 12 120 "Peak upload load"
sleep 20

# Phase 4: Combined Load Test
echo -e "\n${CYAN}🎯 PHASE 4: COMBINED LOAD TEST${NC}"
echo -e "${CYAN}==============================${NC}"

echo -e "${YELLOW}⚠️ Running all services simultaneously - this is the ultimate test!${NC}"

run_test "combined-load" "test-orchestrator.js" 75 300 "All services under combined load"

# Generate final report
echo -e "\n${CYAN}📋 GENERATING FINAL REPORT${NC}"
echo -e "${CYAN}==========================${NC}"

echo -e "${BLUE}📊 Test Summary:${NC}"
ls -la results/*.log | wc -l | xargs echo "   Total test runs:"
echo "   Results directory: $(pwd)/results"

# Check for critical failures
failed_tests=$(grep -l "❌.*failed" results/*.log 2>/dev/null | wc -l || echo "0")
if [ "$failed_tests" -gt 0 ]; then
    echo -e "${RED}⚠️ $failed_tests tests had failures - review logs for details${NC}"
else
    echo -e "${GREEN}✅ All tests completed without critical failures${NC}"
fi

echo -e "\n${GREEN}🎉 Stress testing complete!${NC}"
echo -e "${BLUE}📁 Review detailed logs in the results/ directory${NC}"
echo -e "${YELLOW}💡 Use the monitoring dashboard (npm run monitor) for real-time analysis${NC}"

# Optional: Launch monitoring dashboard
read -p "$(echo -e ${CYAN}🎮 Launch monitoring dashboard now? [y/N]: ${NC})" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}🚀 Starting monitoring dashboard...${NC}"
    node monitoring-dashboard.js
fi