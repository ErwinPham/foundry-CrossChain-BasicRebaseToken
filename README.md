# 🪙 RebaseToken Cross-Chain Project

A fully tested, cross-chain **Rebase Token System** integrating **Vault interest accumulation** and **Chainlink CCIP token bridging** between **Sepolia** and **Arbitrum Sepolia**, built entirely with **Foundry**.

---

## 📘 Overview

This project implements a **Rebase Token** — an ERC20-like token whose balance **automatically grows over time** according to a global interest rate.  

It enables:

✅ Minting and burning via a **Vault** contract (users deposit ETH)  
✅ Linear rebase of balances over time  
✅ Bridging tokens across chains via **Chainlink CCIP Token Pool**  
✅ Synchronizing configurations between **Sepolia ↔ Arbitrum Sepolia**  
✅ Full end-to-end **cross-chain testing** using a local CCIP simulator  

---

## 🧱 Architecture

```
src/
│
├── RebaseToken.sol             # ERC20-compatible token with linear rebase logic
├── RebaseTokenPool.sol         # Custom CCIP TokenPool for cross-chain transfer
├── Vault.sol                   # Handles ETH deposits and redemptions
├── interfaces/
│   └── IRebaseToken.sol        # Interface for Vault <-> Token communication
│
scripts/
│   ├── ConfigurePool.s.sol     # Configures TokenPool relationships (local/remote)
│   ├── BridgeTokens.s.sol      # Bridges tokens between Sepolia and Arbitrum Sepolia
|   └── Deployer.s.sol          # Deployer Token & Pool, Set Permissions and Vault
│
test/
│   ├── RebaseTokenTest.t.sol   # Unit tests for Vault + Token logic
│   └── CrossChainTest.t.sol    # Full simulation of cross-chain bridging via CCIP
```

---

## ⚙️ Contracts Overview

### 1️⃣ RebaseToken.sol
ERC20-like token with **auto-increasing balance** based on time.  
Balance increases according to a global interest rate.  
Core functions:
- `setInterestRate(uint256 newRate)` → only owner, can only **decrease** rate  
- `mint(address to, uint256 amount, uint256 rate)` → called by Vault/Pool  
- `burn(address from, uint256 amount)` → called by Vault/Pool  
- `principleBalanceOf(address)` → returns original principal  

**Core formula:**
```
Balance = Principal × (1 + rate × timeElapsed)
```

---

### 2️⃣ Vault.sol
Handles **ETH deposits and redemptions**.

- On `deposit()` → mints `RebaseToken`
- On `redeem(amount)` → burns token and returns ETH (principal + interest)
- Supports reward injections (`receive()` function)
- Links directly with `RebaseToken` via interface

---

### 3️⃣ RebaseTokenPool.sol
Implements a **custom CCIP TokenPool** for cross-chain mint/burn transfers.

- Sends tokens cross-chain via **Chainlink CCIP**
- Uses **burn & mint** model (no lock/unlock)
- Handles inbound/outbound bridging
- Manages **rate limiter configs** and **remote chain selectors**

---

### 4️⃣ ConfigurePool.s.sol
Deployment & configuration script that:
- Connects two pools (Sepolia ↔ Arbitrum Sepolia)
- Registers allowed remote chains, remote pool addresses, and rate limiters  
- Called once per environment setup

**Example Command:**
```bash
forge script scripts/ConfigurePool.s.sol   --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)"   <localPool> <remoteChainSelector> <remotePool> <remoteToken>   false 0 0 false 0 0   --broadcast --rpc-url $SEPOLIA_RPC_URL
```

---

### 5️⃣ BridgeTokens.s.sol
Provides a **cross-chain transfer execution script**, simulating real-world CCIP usage.

- Uses **ccipSend()** to send tokens from one chain to another  
- Logs message ID and transfer confirmation  
- Supports local test simulation with **CCIPLocalSimulatorFork**

**Example Usage:**
```bash
forge script scripts/BridgeTokens.s.sol   --rpc-url $SEPOLIA_RPC_URL   --private-key $PRIVATE_KEY   --broadcast
```

---

## 🧪 Testing Overview

### ✅ RebaseTokenTest.t.sol
Unit tests for Vault & Token logic:
- Linear balance growth verification
- Deposit / redeem behavior
- Reward injection logic
- Transfer sync & interest rate consistency
- Access control & reversion checks
- Ensure rate only decreases  

**Utilities used:**  
`bound()`, `warp()`, `expectRevert()`, `assertApproxEqAbs()`

---

### 🌐 CrossChainTest.t.sol
Simulates **Sepolia ↔ Arbitrum Sepolia** bridging via CCIP.

- Built with `CCIPLocalSimulatorFork`
- Uses `Register.NetworkDetails` for mock on-chain infra
- Creates two forks, deploys full system on each
- Configures both pools with `applyChainUpdates`
- Validates:
  - Local token burn → remote mint
  - Balance synchronization  
  - Rate limiter configuration  
  - Message delivery confirmation  

---

## 🧰 Setup & Installation

### 🔧 Prerequisites
- Foundry installed  
- Node.js ≥ 18  
- Git  

### 📦 Install
```bash
git clone <repo-url>
cd rebase-token-crosschain
forge install
```

### 🧾 Run All Tests
```bash
forge test -vvv
```

### 🧩 Run Specific Test
```bash
forge test --match-test testBridgeAllTokens -vv
```

### 🌉 Cross-chain Simulation
```bash
forge test --match-path test/CrossChainTest.t.sol -vv
```

---

## 🔗 Chainlink CCIP Simulation

- Uses `@chainlink-local/ccip` library  
- Supports **multi-chain testing** with:
  - `createFork()`
  - `selectFork()`
  - `switchChainAndRouteMessage()`
- Auto-provisions LINK for CCIP fee simulation

💡 **Bridging logic can be tested locally without any live CCIP network.**

---

## 🧠 Key Design Insights
- Interest accrual = **time-based**, not event-based → lower gas usage  
- Vault reward = simple ETH transfer → simulates yield  
- Cross-chain **burn/mint** model → avoids liquidity locks  
- Deterministic multi-chain testing through Foundry  

---

## 🔐 Security Principles
- Only Vault/Pool can call `mint()` or `burn()`  
- Only Owner can modify interest rate  
- Interest rate **cannot increase** (protects users)  
- CCIP rate limiters prevent abuse  

---

## 🧩 Future Improvements
- Dynamic interest rate adjustment based on Vault performance  
- Integration with **Chainlink Price Feeds** for reward valuation  
- Multi-chain scaling to 3+ networks  
- On-chain analytics event indexing  

---

## 👨‍💻 Author
**Developed by:** *Huy Phạm*  
🧠 Smart Contract Developer | 🔗 CCIP Integration | 🧪 Foundry Expert  
