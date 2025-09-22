# DarkEigen Hook 🌊⚡
 UHI6 Hookathon Submission 

 DarkEigenHook is a sophisticated Uniswap V4 hook contract that extends the base BaseHook from V4 periphery, integrating EigenLayer's Actively Validated Services (AVS) for staking and slashing, while adding privacy-focused order execution (to mitigate MEV attacks) and simplified cross-chain swap functionality. It's designed for DeFi applications emphasizing security, decentralization, and interoperability, with built-in protections like reentrancy guards and commit-reveal schemes.

# Video Demo
https://www.veed.io/view/38934740-e4da-4e9a-a978-030b03f87541?source=editor&panel=share

## Features

### 🔐 Privacy & MEV Protection
- **Commit-Reveal Scheme**: Two-phase order execution to prevent frontrunning
- **Time-delayed Execution**: Minimum block delay to protect against MEV attacks
- **Order Hash Privacy**: Orders are committed with hashes before revealing details

### ⚡ EigenLayer AVS Integration
- **Validator Registration**: Stake-based validator system
- **Slashing Mechanism**: Penalize malicious or poorly performing validators
- **Decentralized Validation**: Multiple validators secure cross-chain operations

### 🌐 Cross-Chain Capabilities
- **Cross-Chain Swap Initiation**: Lock tokens on source chain
- **Proof-Based Completion**: Cryptographic proofs for cross-chain verification
- **Multi-Chain Support**: Designed for Ethereum, Polygon, Arbitrum, Optimism

### 🦄 Uniswap v4 Hook Integration
- **Pool Initialization Control**: Enable/disable pools for DarkEigen
- **Pre-Swap Validation**: MEV protection and security checks
- **Post-Swap Processing**: Logging and validation

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   EigenLayer    │    │  Uniswap v4      │    │  Cross-Chain    │
│   Validators    │◄──►│  Pool Manager    │◄──►│  Bridge         │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         ▲                        ▲                        ▲
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DarkEigen Hook                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │   Privacy   │  │    MEV      │  │    Cross-Chain          │ │
│  │ Protection  │  │ Protection  │  │    Operations           │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

1. **Install Foundry**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. **Install Dependencies**
```bash
forge install foundry-rs/forge-std
forge install Uniswap/v4-core
forge install Uniswap/v4-periphery
forge install OpenZeppelin/openzeppelin-contracts
forge install Layr-Labs/eigenlayer-contracts
```

### Setup Environment

1. **Create `.env` file**
```bash
# Private keys (DO NOT COMMIT)
PRIVATE_KEY=your_private_key_here

# RPC URLs
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your-key
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your-key
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/your-key

# API Keys for verification
ETHERSCAN_API_KEY=your_etherscan_api_key
POLYGONSCAN_API_KEY=your_polygonscan_api_key
```

2. **Load environment**
```bash
source .env
```

### Build & Test

```bash
# Build the project
forge build

# Run tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run specific test
forge test --match-test testCommitRevealOrder -vvv

# Coverage report
forge coverage
```

### Deployment

#### Local Development
```bash
# Start local node
anvil

# Deploy to local network
forge script script/DeployDarkEigen.s.sol --rpc-url http://localhost:8545 --broadcast
```

#### Testnet Deployment (Sepolia)
```bash
forge script script/DeployDarkEigen.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

#### Mainnet Deployment
```bash
forge script script/DeployDarkEigen.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

## Usage Examples

### 1. Register as Validator

```solidity
// Register with 10 ETH stake
uint256 stake = 10 ether;
darkEigenHook.registerValidator{value: stake}(stake);
```

### 2. Execute Private Order

```solidity
// Step 1: Commit order hash
bytes32 orderHash = keccak256(abi.encodePacked(
    trader, amount, minAmountOut, deadline, nonce
));
darkEigenHook.commitOrder(orderHash);

// Step 2: Wait for MEV protection delay
// (minimum 2 blocks)

// Step 3: Reveal and execute
darkEigenHook.revealAndExecuteOrder(
    orderHash,
    amount,
    minAmountOut,
    deadline,
    nonce,
    poolKey,
    swapParams
);
```

### 3. Cross-Chain Swap

```solidity
// Initiate cross-chain swap
bytes32 swapHash = darkEigenHook.initiateCrossChainSwap(
    137, // Polygon chain ID
    sourceToken,
    targetToken,
    amount,
    recipient,
    proofHash
);

// Complete on target chain (with proof)
darkEigenHook.completeCrossChainSwap(swapHash, proof);
```

## Security Considerations

### MEV Protection
- **Time Delays**: Minimum 2-block delay between commit and execution
- **Hash Commitments**: Order details hidden until execution
- **Validator Consensus**: Multiple validators must agree on cross-chain operations

### Validator Security
- **Stake Requirements**: Minimum stake required for validator registration
- **Slashing Conditions**: Validators can be slashed for malicious behavior
- **Reputation System**: Track validator performance and reliability

### Cross-Chain Security
- **Proof Verification**: Cryptographic proofs required for cross-chain completion
- **Time Locks**: Delays built into cross-chain operations
- **Multi-Sig Requirements**: Critical operations require multiple signatures

## Gas Optimization

The hook is optimized for gas efficiency:
- **Packed Structs**: Efficient storage layout
- **Minimal External Calls**: Reduced gas costs
- **Batch Operations**: Multiple operations in single transaction
- **State Pruning**: Remove outdated data to free storage

## Testing

### Unit Tests
```bash
forge test --match-contract DarkEigenHookTest
```

### Integration Tests
```bash
forge test --match-test testCrossChain
```

### Fuzz Tests
```bash
forge test --match-test testFuzz
```

## Monitoring & Analytics

### Events to Monitor
- `OrderCommitted`: Track order commitments
- `OrderExecuted`: Monitor successful executions
- `ValidatorSlashed`: Watch for validator penalties
- `CrossChainSwapInitiated`: Track cross-chain activity

### Metrics
- Order execution success rate
- Average MEV protection delay
- Validator uptime and performance
- Cross-chain completion times

## Roadmap

### Phase 1: Core Infrastructure ✅
- [x] Basic hook implementation
- [x] MEV protection mechanisms
- [x] Validator system

### Phase 2: Enhanced Privacy 🔄
- [ ] Zero-knowledge proof integration
- [ ] Advanced privacy features
- [ ] Stealth address support

### Phase 3: Multi-Chain Expansion 🔄
- [ ] Additional chain integrations
- [ ] Cross-chain liquidity pools
- [ ] Unified cross-chain interface

### Phase 4: Advanced Features 📋
- [ ] Flash loan integration
- [ ] Automated MEV redistribution
- [ ] DAO governance system

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Commit changes: `git commit -am 'Add feature'`
4. Push to branch: `git push origin feature-name`
5. Submit a Pull Request

## Security Audits

Before mainnet deployment:
- [ ] Internal security review
- [ ] External audit (TBD)
- [ ] Bug bounty program
- [ ] Testnet deployment and monitoring

## License

MIT License - see LICENSE file for details


## Support

- GitHub Issues: Report bugs and feature requests
- Documentation: [Coming Soon]
- Discord: [Community Link TBD]

---

**Built with ❤️ for the future of decentralized finance**
