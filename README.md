# Uniswap V3 Proxy Contract

A Solidity smart contract system using the ERC-1967 proxy pattern that allows users to deposit an ERC20 token and ETH, which are then used to create a Uniswap V3 liquidity position.

## Architecture

```
User
 │
 ▼
UniswapPositionProxy (ERC-1967)
 │  delegatecall
 ▼
UniswapPositionManager (Implementation)
 │
 ├── Wraps ETH → WETH
 ├── Sorts tokens (token0 < token1)
 ├── Creates & initializes pool (if needed)
 ├── Mints Uniswap V3 position
 └── Refunds unused tokens
```

### Contracts

| Contract | Description |
|---|---|
| **UniswapPositionManager** | Implementation/logic contract. Handles deposits, WETH wrapping, and Uniswap V3 position minting. |
| **UniswapPositionProxy** | Minimal ERC-1967 proxy. Delegates all calls to the implementation. Supports upgrades via `upgradeTo()`. |
| **TestToken** | ERC20 test token (TKA) with 1M supply, used as Asset A for testing. |
| **MockWETH** | Mock Wrapped Ether contract for testnet deployment. |
| **MockPositionManager** | Mock Uniswap V3 NonfungiblePositionManager that simulates pool creation and position minting. |

### How It Works

1. User approves the proxy contract to spend their ERC20 tokens.
2. User calls `createPosition()` on the proxy, sending ERC20 tokens + ETH.
3. The implementation contract (via delegatecall):
   - Pulls ERC20 tokens from the user.
   - Wraps ETH into WETH.
   - Sorts tokens to satisfy Uniswap's `token0 < token1` requirement.
   - Optionally creates and initializes the pool if it doesn't exist.
   - Approves the NonfungiblePositionManager and mints a liquidity position.
   - Refunds any unused tokens back to the user.

## Deployed Contracts (zkSync Era Sepolia Testnet)

| Contract | Address |
|---|---|
| UniswapPositionManager (Implementation) | [`0x8CF72077B7DE3E1b2A77339461337C91aCBe0E20`](https://sepolia.explorer.zksync.io/address/0x8CF72077B7DE3E1b2A77339461337C91aCBe0E20) |
| UniswapPositionProxy | [`0x9C8F3e02370b98F8Cfc44c59068BCE1347dfe280`](https://sepolia.explorer.zksync.io/address/0x9C8F3e02370b98F8Cfc44c59068BCE1347dfe280) |
| TestToken (TKA) | [`0xFE8F85B89B23b3E7814F1b98f41491eA400c40FF`](https://sepolia.explorer.zksync.io/address/0xFE8F85B89B23b3E7814F1b98f41491eA400c40FF) |
| MockWETH | [`0xE01Ebe5328916FEC7fDc7F2C95FC4A2e8D4590ad`](https://sepolia.explorer.zksync.io/address/0xE01Ebe5328916FEC7fDc7F2C95FC4A2e8D4590ad) |
| MockPositionManager | [`0x9718b5C323A9b62B6F33f70AFBf391bCE6f0Bf17`](https://sepolia.explorer.zksync.io/address/0x9718b5C323A9b62B6F33f70AFBf391bCE6f0Bf17) |

## Transactions

| Action | Transaction Hash |
|---|---|
| Token Approval | [`0x41f34f2ff75addd477b9eacea41af18ac4b4a0fba37c3edc7b4de151acef5d7f`](https://sepolia.explorer.zksync.io/tx/0x41f34f2ff75addd477b9eacea41af18ac4b4a0fba37c3edc7b4de151acef5d7f) |
| Create Position | [`0x989099bd802a9627dd9b7d9b6eb79be34604b29a2f443384b9009b27c9cc021d`](https://sepolia.explorer.zksync.io/tx/0x989099bd802a9627dd9b7d9b6eb79be34604b29a2f443384b9009b27c9cc021d) |

## Proxy Pattern Details

The contract uses the **ERC-1967 Transparent Proxy** pattern:

- **Implementation slot**: `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
- **Admin slot**: `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
- The proxy admin can upgrade the implementation via `upgradeTo(address)`.
- State is stored in the proxy's storage, not the implementation's.
- `initialize()` replaces the constructor and can only be called once.

## Deployment Steps

### 1. Compile

- Open Remix, paste the contract files.
- Set compiler to `0.8.20`, EVM version `paris`, enable optimization (200 runs).
- Use the zkSync Remix plugin (ZKSYNC tab) to compile with zksolc.

### 2. Deploy (in order)

1. **TestToken** — no constructor args. Mints 1M TKA to deployer.
2. **MockWETH** — no constructor args.
3. **MockPositionManager** — no constructor args.
4. **UniswapPositionManager** — no constructor args (implementation/logic contract).
5. **UniswapPositionProxy** — constructor args:
   - `impl`: UniswapPositionManager address
   - `initData`: ABI-encoded `initialize(MockPositionManager, MockWETH, yourWallet)`

   Encode `initData` in the Remix console:
   ```javascript
   web3.eth.abi.encodeFunctionCall({
       name: 'initialize',
       type: 'function',
       inputs: [
           { type: 'address', name: '_positionManager' },
           { type: 'address', name: '_weth' },
           { type: 'address', name: '_owner' }
       ]
   }, ['MOCK_POSITION_MANAGER_ADDR', 'MOCK_WETH_ADDR', 'YOUR_WALLET_ADDR'])
   ```

### 3. Verify all contracts on the zkSync Sepolia explorer.

### 4. Create a Position

1. On the explorer, go to **TestToken** → Write → call `approve(proxyAddress, 1000000000000000000)`.
2. On the explorer, go to **UniswapPositionProxy** → Write as Proxy → call `createPosition`:
   - `payableAmount`: `0.01` (ether)
   - `tokenA`: TestToken address
   - `amountA`: `1000000000000000000` (1 TKA)
   - `fee`: `3000`
   - `tickLower`: `-887220`
   - `tickUpper`: `887220`
   - `sqrtPriceX96`: `79228162514264337593543950336`

## Testnet Note

Uniswap V3 is not officially deployed on zkSync Era Sepolia Testnet. To demonstrate the full flow on testnet, mock contracts (MockWETH, MockPositionManager) were deployed to simulate the Uniswap V3 NonfungiblePositionManager behavior. The core contract logic (`UniswapPositionManager` + `UniswapPositionProxy`) is production-ready and works with real Uniswap V3 deployments on zkSync Era Mainnet by passing the real addresses during initialization:

- NonfungiblePositionManager: `0x0616e5762c1E7Dc3723c50663dF10a162D690a86`
- WETH: `0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91`

## Compilation Settings

- Solidity: `0.8.20`
- EVM version: `paris`
- Optimizer: enabled (200 runs)
- Tooling: Remix IDE + zkSync plugin (zksolc)
