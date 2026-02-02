# Linera Roulette

Multiplayer roulette game on Linera microchains with real-time cross-chain gameplay.

## Features

- **Real-time Multiplayer**: Cross-chain gameplay with host/join mode
- **Verifiable RNG**: On-chain random number generation
- **13 Bet Types**: Straight, split, street, corner, line, column, dozen, red/black, odd/even, high/low
- **Live on Conway Testnet**: 20 chains deployed and operational

## Tech Stack

- **Backend**: Rust + Linera SDK 0.15.11
- **Frontend**: React + TypeScript + Vite + TailwindCSS
- **Network**: Conway Testnet (Linera)

## Run Locally

```bash
./run.bash
```

## Deploy to Conway Testnet

```bash
./deploy.sh
```

## Live Deployment

- **App ID**: `a204d053e0a7cf735df997e23e4d2d5e9c61cf3f539fcfdab1e6a737a0279da8c1e97e53240f5b8a86b1f2de7aa99b05f82bc2dbc8eb64ec2b419f98d3f17f5a`
- **Network**: Conway Testnet
- **Chains**: 20 deployed game rooms

## Game Modes

1. **Solo**: Play on your own chain
2. **Host**: Create a room for others to join
3. **Join**: Connect to an existing game room

## Architecture

- Microchain-based state isolation
- Host chain manages game state
- Player chains handle bets via cross-chain messages
- Deterministic RNG using block timestamps and chain IDs
