#!/bin/bash

# Setup script for I2P Bridge stress testing environment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}🔧 I2P Bridge Stress Test Setup${NC}"
echo -e "${CYAN}==============================${NC}"

# Check Node.js version
echo -e "${BLUE}🔍 Checking Node.js version...${NC}"
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js is not installed${NC}"
    echo -e "${YELLOW}💡 Please install Node.js 16+ from https://nodejs.org${NC}"
    exit 1
fi

NODE_VERSION=$(node --version | sed 's/v//')
MAJOR_VERSION=$(echo $NODE_VERSION | cut -d. -f1)

if [ "$MAJOR_VERSION" -lt 16 ]; then
    echo -e "${RED}❌ Node.js version $NODE_VERSION is too old${NC}"
    echo -e "${YELLOW}💡 Please upgrade to Node.js 16 or later${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Node.js $NODE_VERSION detected${NC}"

# Check npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}❌ npm is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ npm $(npm --version) detected${NC}"

# Install dependencies
echo -e "\n${BLUE}📦 Installing stress test dependencies...${NC}"
npm install

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Dependencies installed successfully${NC}"
else
    echo -e "${RED}❌ Failed to install dependencies${NC}"
    exit 1
fi

# Create necessary directories
echo -e "\n${BLUE}📁 Creating directories...${NC}"
mkdir -p results
mkdir -p test-files
mkdir -p logs

echo -e "${GREEN}✅ Directories created${NC}"

# Check API key
echo -e "\n${BLUE}🔑 Checking API key configuration...${NC}"
if [ -z "$I2P_BRIDGE_API_KEY" ]; then
    echo -e "${YELLOW}⚠️ API key not set as environment variable${NC}"
    echo -e "${BLUE}💡 You can set it with:${NC}"
    echo -e "${CYAN}   export I2P_BRIDGE_API_KEY=your-api-key-here${NC}"
    echo -e "\n${BLUE}📝 Or create a .env file based on .env.example${NC}"
    
    # Check if .env.example exists and offer to copy it
    if [ -f ".env.example" ]; then
        echo -e "${BLUE}📋 Found .env.example file${NC}"
        read -p "$(echo -e ${YELLOW}Would you like to copy .env.example to .env? [y/N]: ${NC})" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp .env.example .env
            echo -e "${GREEN}✅ Created .env file - please edit it with your API key${NC}"
        fi
    fi
else
    echo -e "${GREEN}✅ API key environment variable is set${NC}"
fi

# Test basic connectivity
echo -e "\n${BLUE}🌐 Testing bridge server connectivity...${NC}"
if curl -s --max-time 10 https://bridge.stormycloud.org/api/v1/debug > /dev/null; then
    echo -e "${GREEN}✅ Bridge server is reachable${NC}"
else
    echo -e "${YELLOW}⚠️ Bridge server connectivity test failed${NC}"
    echo -e "${BLUE}   This may be normal if the server requires authentication${NC}"
fi

# Make scripts executable
echo -e "\n${BLUE}🔧 Setting script permissions...${NC}"
chmod +x run-all-tests.sh quick-test.sh

echo -e "${GREEN}✅ Scripts made executable${NC}"

# Setup complete
echo -e "\n${GREEN}🎉 Setup completed successfully!${NC}"
echo -e "\n${CYAN}📚 Next Steps:${NC}"
echo -e "${BLUE}1. Set your API key: export I2P_BRIDGE_API_KEY=your-key${NC}"
echo -e "${BLUE}2. Run quick test: ./quick-test.sh${NC}"
echo -e "${BLUE}3. Run full tests: ./run-all-tests.sh${NC}"
echo -e "${BLUE}4. Start monitoring: npm run monitor${NC}"
echo -e "\n${YELLOW}📖 See USAGE_GUIDE.md for detailed instructions${NC}"

# Show available commands
echo -e "\n${CYAN}📋 Available Commands:${NC}"
echo -e "${BLUE}   ./quick-test.sh              - Quick validation test${NC}"
echo -e "${BLUE}   ./run-all-tests.sh           - Comprehensive test suite${NC}"
echo -e "${BLUE}   npm run monitor              - Real-time dashboard${NC}"
echo -e "${BLUE}   npm run test:light           - Light load test${NC}"
echo -e "${BLUE}   npm run test:medium          - Medium load test${NC}"
echo -e "${BLUE}   npm run test:heavy           - Heavy load test${NC}"