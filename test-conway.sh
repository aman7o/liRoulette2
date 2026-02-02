#!/bin/bash
set -e

echo "🎰 =================================================="
echo "🎰  LINERA ROULETTE - CONWAY TESTNET TESTER"
echo "🎰 =================================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if Linera is installed
if ! command -v linera &> /dev/null; then
    echo -e "${RED}ERROR: Linera CLI not found${NC}"
    echo "Please install Linera from: https://linera.dev"
    exit 1
fi

# Check if Node.js is installed
if ! command -v npm &> /dev/null; then
    echo -e "${RED}ERROR: Node.js/npm not found${NC}"
    echo "Please install Node.js from: https://nodejs.org"
    exit 1
fi

echo -e "${BLUE}📋 Pre-flight checks passed!${NC}"
echo ""

# Step 1: Setup environment
echo -e "${YELLOW}⚙️  Step 1/4: Setting up environment...${NC}"
cd frontend

if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${GREEN}✅ Created .env from .env.example${NC}"
else
    echo -e "${GREEN}✅ .env already exists${NC}"
fi
cd ..
echo ""

# Step 2: Install frontend dependencies
echo -e "${YELLOW}📦 Step 2/4: Installing frontend dependencies...${NC}"
cd frontend
if [ ! -d node_modules ]; then
    npm install
    echo -e "${GREEN}✅ Dependencies installed${NC}"
else
    echo -e "${GREEN}✅ Dependencies already installed${NC}"
fi
cd ..
echo ""

# Step 3: Start Linera service
echo -e "${YELLOW}🌐 Step 3/4: Starting Linera service...${NC}"

# Check for existing wallet
if [ -f ~/.linera-testnet/wallet.json ]; then
    export LINERA_WALLET="$HOME/.linera-testnet/wallet.json"
    export LINERA_STORAGE="rocksdb:$HOME/.linera-testnet/client.db"
    echo -e "${BLUE}   Using Conway testnet wallet${NC}"
elif [ -f "$HOME/Library/Application Support/linera/wallet.json" ]; then
    export LINERA_WALLET="$HOME/Library/Application Support/linera/wallet.json"
    export LINERA_STORAGE="rocksdb:$HOME/Library/Application Support/linera/client.db"
    echo -e "${BLUE}   Using default wallet${NC}"
else
    echo -e "${RED}ERROR: No Linera wallet found${NC}"
    echo "Please initialize a wallet first:"
    echo "  linera wallet init --with-new-chain --faucet https://faucet.testnet-conway.linera.net/"
    exit 1
fi

linera service --port 8080 > /tmp/linera-service.log 2>&1 &
LINERA_PID=$!
sleep 3

if ps -p $LINERA_PID > /dev/null; then
    echo -e "${GREEN}✅ Linera service started (PID: $LINERA_PID)${NC}"
    echo -e "${BLUE}   Connected to Conway Testnet${NC}"
    echo -e "${BLUE}   Running on http://localhost:8080${NC}"
else
    echo -e "${RED}ERROR: Failed to start Linera service${NC}"
    cat /tmp/linera-service.log
    exit 1
fi
echo ""

# Step 4: Start frontend
echo -e "${YELLOW}🚀 Step 4/4: Starting frontend...${NC}"
cd frontend
echo -e "${GREEN}✅ Frontend starting at http://localhost:5173${NC}"
echo ""
echo -e "${BLUE}=================================================="
echo -e "🎰  LINERA ROULETTE IS READY!"
echo -e "=================================================="
echo -e ""
echo -e "🌐 Open your browser: ${GREEN}http://localhost:5173${NC}"
echo -e "🎮 Testing live Conway Testnet deployment"
echo -e "🔗 App ID: a204d0538ae511fe0fa89ff4483ea2282d221999044274f87aa8be9ea84e340a"
echo -e ""
echo -e "Press ${RED}Ctrl+C${NC} to stop both services"
echo -e "=================================================="${NC}
echo ""

# Run frontend (this will block)
npm run dev

# Cleanup on exit
trap "echo ''; echo 'Stopping services...'; kill $LINERA_PID 2>/dev/null || true; echo 'Done!'" EXIT
