#!/bin/bash
set -e

# Color output variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Testnet configuration
TESTNET_FAUCET="https://faucet.testnet-conway.linera.net/"
DATA_DIR="${DATA_DIR:-/data/linera}"
SERVICE_PORT="${SERVICE_PORT:-8080}"
CHAIN_POOL_SIZE=20

# Banner
echo -e "${BLUE}🎰 LINERA ROULETTE - CONWAY TESTNET DEPLOYMENT${NC}"
echo -e "${BLUE}================================================${NC}\n"

# ============================================================
# SECTION 1: Prerequisites Check
# ============================================================
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check linera CLI
if ! command -v linera &> /dev/null; then
    echo -e "${RED}Error: linera CLI not found${NC}"
    echo -e "${YELLOW}Install from: https://github.com/linera-io/linera-protocol${NC}"
    exit 1
fi

# Check version (must be 0.15.x)
LINERA_VERSION=$(linera --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
MAJOR_MINOR=$(echo "$LINERA_VERSION" | cut -d. -f1-2)
if [ "$MAJOR_MINOR" != "0.15" ]; then
    echo -e "${RED}Error: Requires Linera v0.15.x, found v$LINERA_VERSION${NC}"
    echo -e "${YELLOW}Install compatible version using: cargo install linera-service@0.15.11${NC}"
    exit 1
fi

# Check cargo
if ! command -v cargo &> /dev/null; then
    echo -e "${RED}Error: cargo not found${NC}"
    echo -e "${YELLOW}Install Rust from: https://rustup.rs${NC}"
    exit 1
fi

# Check npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}Error: npm not found${NC}"
    echo -e "${YELLOW}Install Node.js from: https://nodejs.org${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites satisfied (Linera v$LINERA_VERSION)${NC}\n"

# ============================================================
# SECTION 2: Persistent Storage Setup
# ============================================================
echo -e "${YELLOW}Setting up persistent storage...${NC}"

# Create data directory
mkdir -p "$DATA_DIR"
WALLET_PATH="$DATA_DIR/wallet.json"
STORAGE_PATH="rocksdb:$DATA_DIR/linera.db"

# Check if wallet exists
if [ -f "$WALLET_PATH" ]; then
    echo -e "${YELLOW}Warning: Wallet already exists at $WALLET_PATH${NC}"
    read -p "Overwrite existing wallet? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Deployment cancelled${NC}"
        exit 1
    fi
    # Backup existing wallet
    BACKUP_PATH="$DATA_DIR/wallet.backup.$(date +%s).json"
    cp "$WALLET_PATH" "$BACKUP_PATH"
    echo -e "${GREEN}✓ Backed up existing wallet to $BACKUP_PATH${NC}"
    # Clean up storage
    rm -rf "$DATA_DIR/linera.db"
fi

# Set environment variables
export LINERA_WALLET="$WALLET_PATH"
export LINERA_STORAGE="$STORAGE_PATH"

echo -e "${GREEN}✓ Storage configured: $DATA_DIR${NC}\n"

# ============================================================
# SECTION 3: Wallet Initialization
# ============================================================
echo -e "${YELLOW}Initializing wallet from Conway testnet...${NC}"

# Initialize wallet with testnet faucet (automatically creates first chain)
INIT_OUTPUT=$(linera wallet init --faucet "$TESTNET_FAUCET" 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Wallet initialization failed${NC}"
    echo "$INIT_OUTPUT"
    echo -e "${YELLOW}Check testnet faucet availability: $TESTNET_FAUCET${NC}"
    exit 1
fi

# Extract default chain
DEFAULT_CHAIN=$(linera wallet show | grep "Chain ID:" | awk '{print $3}' | head -1)

if [ -z "$DEFAULT_CHAIN" ]; then
    echo -e "${RED}Error: Could not extract default chain${NC}"
    linera wallet show
    exit 1
fi

echo -e "${GREEN}✓ Wallet initialized${NC}"
echo -e "${BLUE}Default chain: $DEFAULT_CHAIN${NC}\n"

# ============================================================
# SECTION 4: Contract Build
# ============================================================
echo -e "${YELLOW}Building contract to WASM...${NC}"

# Add WASM target
rustup target add wasm32-unknown-unknown > /dev/null 2>&1

# Build contract
cd contract
cargo build --release --target wasm32-unknown-unknown

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Contract build failed${NC}"
    exit 1
fi
cd ..

# Verify artifacts exist
CONTRACT_WASM="contract/target/wasm32-unknown-unknown/release/linera_roulette_contract.wasm"
SERVICE_WASM="contract/target/wasm32-unknown-unknown/release/linera_roulette_service.wasm"

if [ ! -f "$CONTRACT_WASM" ] || [ ! -f "$SERVICE_WASM" ]; then
    echo -e "${RED}Error: WASM artifacts not found${NC}"
    echo -e "${YELLOW}Expected files:${NC}"
    echo -e "  - $CONTRACT_WASM"
    echo -e "  - $SERVICE_WASM"
    exit 1
fi

echo -e "${GREEN}✓ Contract built successfully${NC}\n"

# ============================================================
# SECTION 5: Contract Deployment
# ============================================================
echo -e "${YELLOW}Deploying contract to Conway testnet...${NC}"

# Deploy contract
APP_OUTPUT=$(linera publish-and-create \
    "$CONTRACT_WASM" \
    "$SERVICE_WASM" \
    --json-argument '{}' \
    2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Contract deployment failed${NC}"
    echo "$APP_OUTPUT"
    exit 1
fi

# Extract APP_ID (64-char hex)
APP_ID=$(echo "$APP_OUTPUT" | grep -oE '[a-f0-9]{64}' | tail -1)

if [ -z "$APP_ID" ]; then
    echo -e "${RED}Error: Could not extract APP_ID${NC}"
    echo -e "${YELLOW}Deployment output:${NC}"
    echo "$APP_OUTPUT"
    exit 1
fi

echo -e "${GREEN}✓ Contract deployed${NC}"
echo -e "${BLUE}APP_ID: $APP_ID${NC}\n"

# Save to file for reference
echo "$APP_ID" > "$DATA_DIR/app_id.txt"

# ============================================================
# SECTION 6: Chain Pool Creation
# ============================================================
echo -e "${YELLOW}Creating chain pool (${CHAIN_POOL_SIZE} chains)...${NC}"

# Initialize array with default chain
CHAIN_POOL=("$DEFAULT_CHAIN")
echo -e "${BLUE}Chain 1/$CHAIN_POOL_SIZE: $DEFAULT_CHAIN (default)${NC}"

# Create remaining chains
for i in $(seq 2 $CHAIN_POOL_SIZE); do
    echo -ne "${BLUE}Creating chain $i/$CHAIN_POOL_SIZE...${NC}"

    # Create chain derived from default chain
    CHAIN_OUTPUT=$(linera open-chain --from "$DEFAULT_CHAIN" 2>&1)

    if [ $? -eq 0 ]; then
        CHAIN_ID=$(echo "$CHAIN_OUTPUT" | grep -oE '[a-f0-9]{64}' | tail -1)

        if [ -n "$CHAIN_ID" ]; then
            CHAIN_POOL+=("$CHAIN_ID")
            echo -e "\r${GREEN}✓ Chain $i/$CHAIN_POOL_SIZE created${NC}"
            # Rate limiting: wait 1 second between requests
            sleep 1
        else
            echo -e "\r${YELLOW}⚠ Chain $i/$CHAIN_POOL_SIZE: Failed to extract chain ID, skipping${NC}"
        fi
    else
        echo -e "\r${YELLOW}⚠ Chain $i/$CHAIN_POOL_SIZE: Creation failed, skipping${NC}"
        # Continue on error (testnet faucet may be rate-limited)
    fi
done

echo -e "\n${GREEN}✓ Chain pool created (${#CHAIN_POOL[@]} chains)${NC}\n"

# Sync chains
echo -e "${YELLOW}Synchronizing chains...${NC}"
linera sync > /dev/null 2>&1 || true
echo -e "${GREEN}✓ Chains synchronized${NC}\n"

# ============================================================
# SECTION 7: Frontend Configuration
# ============================================================
echo -e "${YELLOW}Generating frontend configuration...${NC}"

cd frontend

# Generate .env file
cat > .env << EOF
# Conway Testnet Configuration
# Generated by deploy.sh on $(date)

VITE_NODE_URL=http://localhost:$SERVICE_PORT
VITE_FAUCET_URL=$TESTNET_FAUCET
VITE_APP_ID=$APP_ID
VITE_DEFAULT_CHAIN=$DEFAULT_CHAIN
VITE_HOST_CHAIN=$DEFAULT_CHAIN
EOF

# Generate chainPool.json
echo '{"chains":[' > public/chainPool.json
for i in "${!CHAIN_POOL[@]}"; do
    COMMA=""
    [ $i -gt 0 ] && COMMA=","
    CHAIN_ID="${CHAIN_POOL[$i]}"
    echo "${COMMA}{\"id\":$((i+1)),\"chainId\":\"$CHAIN_ID\",\"inUse\":false}" >> public/chainPool.json
done
echo ']}' >> public/chainPool.json

# Generate rooms.json (use first 3 chains)
cat > public/rooms.json << EOF
{
  "rooms": [
    {"id": 1, "name": "Room 1 - Beginner's Table", "chainId": "${CHAIN_POOL[0]}"},
    {"id": 2, "name": "Room 2 - High Rollers", "chainId": "${CHAIN_POOL[1]:-${CHAIN_POOL[0]}}"},
    {"id": 3, "name": "Room 3 - VIP Lounge", "chainId": "${CHAIN_POOL[2]:-${CHAIN_POOL[0]}}"}
  ]
}
EOF

cd ..

echo -e "${GREEN}✓ Frontend configured${NC}\n"

# ============================================================
# SECTION 8: Final Output & Instructions
# ============================================================
echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}🎉 DEPLOYMENT SUCCESSFUL!${NC}"
echo -e "${GREEN}================================================${NC}"

echo -e "\n${BLUE}Deployment Summary:${NC}"
echo -e "  APP_ID:        $APP_ID"
echo -e "  DEFAULT_CHAIN: $DEFAULT_CHAIN"
echo -e "  CHAINS:        ${#CHAIN_POOL[@]} total"
echo -e "  STORAGE:       $DATA_DIR"

echo -e "\n${BLUE}Next Steps:${NC}"
echo -e "${YELLOW}1. Start the GraphQL service (terminal 1):${NC}"
echo -e "   export LINERA_WALLET=\"$WALLET_PATH\""
echo -e "   export LINERA_STORAGE=\"$STORAGE_PATH\""
echo -e "   linera service --port $SERVICE_PORT"

echo -e "\n${YELLOW}2. Start the frontend (terminal 2):${NC}"
echo -e "   cd frontend"
echo -e "   npm install  # If not done already"
echo -e "   npm run dev"

echo -e "\n${YELLOW}3. Access the application:${NC}"
echo -e "   http://localhost:5173"

echo -e "\n${BLUE}Configuration files created:${NC}"
echo -e "  - frontend/.env"
echo -e "  - frontend/public/chainPool.json"
echo -e "  - frontend/public/rooms.json"
echo -e "  - $DATA_DIR/app_id.txt"

echo -e "\n${BLUE}For more details, see DEPLOY_TESTNET.md${NC}\n"
