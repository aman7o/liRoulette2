# Linera Roulette

A fully functional decentralized roulette game built on Linera blockchain, demonstrating real-time cross-chain gameplay through microchain architecture.

## Overview

Linera Roulette is a production-ready blockchain gaming application that leverages Linera's microchain technology to enable true multiplayer gaming with state isolation and cross-chain messaging. Each player operates on their own microchain while seamlessly interacting with a shared game state hosted on a coordinator chain.

## Key Features

### Blockchain Gaming
- **Real-time Multiplayer**: Host and join game rooms across different microchains
- **On-Chain RNG**: Verifiable random number generation using blockchain timestamps and chain IDs
- **Complete Roulette Experience**: All 13 standard bet types (straight, split, street, corner, line, column, dozen, red/black, odd/even, high/low)
- **State Isolation**: Each player maintains their own balance and bet history on their personal microchain

### Technical Achievements
- **Cross-Chain Messaging**: Seamless communication between player chains and host chain
- **Scalable Architecture**: 20 pre-deployed microchains ready for multiplayer sessions
- **Responsive UI**: Adaptive zoom levels per game mode (1x for solo, 0.85x for multiplayer)
- **Production Deployment**: Live on Conway Testnet with persistent state

## Technology Stack

**Smart Contract (Backend)**
- Language: Rust
- Framework: Linera SDK 0.15.7
- Architecture: Microchain-based state machine
- Messaging: Cross-chain message passing

**Frontend**
- Framework: React 18 + TypeScript
- Build Tool: Vite
- Styling: TailwindCSS
- GraphQL: Client-side queries via graphql-request
- Animation: anime.js for wheel physics

**Infrastructure**
- Network: Conway Testnet (Linera)
- Storage: RocksDB for persistent state
- Deployment: 20 microchains with load balancing

## Architecture

### Microchain Design

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│  Player Chain 1 │◄────►│   Host Chain    │◄────►│  Player Chain 2 │
│                 │      │                 │      │                 │
│  - Own balance  │      │  - Game state   │      │  - Own balance  │
│  - Own bets     │      │  - All players  │      │  - Own bets     │
│  - Bet history  │      │  - RNG logic    │      │  - Bet history  │
└─────────────────┘      └─────────────────┘      └─────────────────┘
```

### State Management

**Player Chain State:**
- Player registration and balance
- Individual bet placement
- Personal game history
- Isolated from other players

**Host Chain State:**
- Global game state (spinning, betting, settled)
- All player registrations
- Current round bets from all players
- RNG execution and result distribution
- Payout calculations

### Cross-Chain Communication

1. **Player Registration**: Player chain → Host chain (register player)
2. **Bet Placement**: Player chain → Host chain (place bet)
3. **Spin Request**: Any player → Host chain (trigger spin)
4. **Result Distribution**: Host chain → Player chains (broadcast results)

### Random Number Generation

Deterministic on-chain RNG using:
- Block timestamp
- Chain ID
- Round number
- SHA-256 hashing

Ensures verifiable fairness while maintaining blockchain determinism.

## Game Modes

**Solo Mode**
- Single-player experience
- Play on your own microchain
- Full-size UI (1x zoom) for optimal visibility

**Host Mode**
- Create a multiplayer game room
- Manage game state and timing
- Coordinate spins across all players
- Optimized UI (0.85x zoom) for better overview

**Join Mode**
- Connect to an existing game room
- Place bets alongside other players
- Wait for host to spin wheel
- Synchronized results across all players

## Quick Start

### Prerequisites
- Linera CLI installed
- Node.js 18+ and npm
- Rust toolchain (for local builds)

### Test Live Deployment

One command to connect to the live Conway Testnet deployment:

```bash
./test-conway.sh
```

This will:
1. Set up environment configuration
2. Install frontend dependencies
3. Start Linera service (connects to Conway Testnet)
4. Launch frontend at http://localhost:5173

### Run Local Development

Full local network with contract deployment:

```bash
./run.bash
```

This will:
1. Start a local Linera network
2. Build and deploy the smart contract
3. Create 20 microchains for multiplayer
4. Launch two frontend instances for testing
5. Open at http://localhost:5173 and http://localhost:5174

### Deploy to Conway Testnet

```bash
./deploy.sh
```

Deploys a new instance with fresh microchains.

## Live Deployment Information

**Conway Testnet Deployment:**
- **App ID**: `a204d0538ae511fe0fa89ff4483ea2282d221999044274f87aa8be9ea84e340a`
- **Network**: Conway Testnet (public Linera testnet)
- **Microchains**: 20 pre-deployed game rooms
- **Status**: Production-ready and operational

## Testing Guide

### Manual Testing

1. **Solo Mode Testing**
   - Register a player
   - Place various bet types
   - Spin wheel
   - Verify payout calculations

2. **Multiplayer Testing**
   - Open two browser windows
   - Register different players
   - One hosts, one joins
   - Both place bets
   - Host spins wheel
   - Verify synchronized results

3. **Cross-Chain Verification**
   - Check player balances on individual chains
   - Verify bet history isolation
   - Confirm host chain aggregates all state

### Bet Types Verification

Test all 13 bet types:
- Straight (single number): 35:1 payout
- Split (two numbers): 17:1 payout
- Street (three numbers): 11:1 payout
- Corner (four numbers): 8:1 payout
- Line (six numbers): 5:1 payout
- Column: 2:1 payout
- Dozen: 2:1 payout
- Red/Black: 1:1 payout
- Odd/Even: 1:1 payout
- High/Low: 1:1 payout

## Project Structure

```
.
├── contract/                 # Rust smart contract
│   ├── src/
│   │   ├── lib.rs           # Application trait implementation
│   │   ├── state.rs         # State definitions
│   │   ├── contract.rs      # Contract binary (operations)
│   │   └── service.rs       # Service binary (queries)
│   └── Cargo.toml
├── frontend/                 # React frontend
│   ├── src/
│   │   ├── components/      # UI components
│   │   ├── contexts/        # React contexts
│   │   ├── hooks/           # Custom hooks
│   │   └── types/           # TypeScript types
│   └── package.json
├── run.bash                  # Local development launcher
├── test-conway.sh           # Conway testnet tester
├── deploy.sh                # Testnet deployment script
└── README.md
```

## Technical Highlights

**Smart Contract Design:**
- Efficient state management with minimal storage overhead
- Optimized cross-chain message handling
- Deterministic RNG for provable fairness
- Comprehensive error handling

**Frontend Engineering:**
- Type-safe GraphQL queries
- Real-time state updates
- Responsive design with mode-specific layouts
- Sound effects and animations for user engagement
- Automatic port conflict resolution

**DevOps:**
- One-command setup for judges
- Automated dependency installation
- Graceful cleanup on exit
- Clear error messages and logging

## Known Limitations

- RNG is deterministic (block-based) - suitable for demo, not casino-grade
- Conway Testnet may have intermittent availability
- Multiplayer requires manual coordination (no matchmaking)

## Future Enhancements

- WebSocket support for real-time updates
- Persistent leaderboards
- Tournament mode with prize pools
- Enhanced RNG with VRF (Verifiable Random Function)
- Mobile-responsive design

## License

MIT License

## Contact

For questions or issues, please open a GitHub issue.

---

**Built for Linera Blockchain** | **Conway Testnet Ready** | **Production Grade**
