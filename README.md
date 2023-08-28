## *baseloop* 🔵🔁

*Using Compound III to one-click leverage on cbETH (up to 10x!!!)*

---

Gas efficient with minimal "trips":
1. Flash loan cbETH from Aave V3
2. Supply (collateralize) cbETH on Compound III
3. Borrow ETH on Compound III
4. Swap ETH for cbETH on Uniswap V3
5. Repay the flash loan

---

## Usage

### The one-click leverage does not have a UI. You will need to use *basescan*

* [cbETH APY Calculator](https://docs.google.com/spreadsheets/d/1mLf3QrqNqqyDjQtOqL1UxRTSkgItmWxmjMAqI8ppAnw)
* [Basescan contract](https://basescan.org/address/0xdb318ffe6a10748bced949bdd35f7b087e2a05f0)


> Note: You must allow Baseloop to manage your Compound balances
> ```bash
> cast send 0x46e6b214b524310239732D51387075E0e70970bf "allow(address,bool)" 0xDB318ffe6A10748BCeD949bdd35F7B087e2A05F0 true --rpc-url https://mainnet.base.org --interactive
> ```

Docs:

**[createPositionWithETH](https://basescan.org/address/0xdb318ffe6a10748bced949bdd35f7b087e2a05f0#writeContract#F3)**

    - payableAmount: the initial amount of Ether

    - leverageMultiplier: the desired leverage, relative to the above Ether amount. Expressed with 18 decimals. 2.5e18 = 2.5x leverage, 2500000000000000000

    - collateralFactor: desired collateral factor (or "loan-to-value"). Expressed with 18 decimals. 0.8e18 = 80% collateral factor, 800000000000000000

    - cbETHPrice: price of cbETH, in Ether. Expressed with 18 decimals. 1.05e18 = 1.05 ETH per cbETH token, 1050000000000000000
*read cbETHPrice from [chainlink](https://data.chain.link/base/base/crypto-eth/cbeth-eth) or [compound](https://app.compound.finance/markets?market=weth-basemainnet)*

**[createPositionWithWETH](https://basescan.org/address/0xdb318ffe6a10748bced949bdd35f7b087e2a05f0#writeContract#F4)**
* similar to above, but use WETH. You must approve Baseloop to spend your WETH

**[createPositionWithCBETH](https://basescan.org/address/0xdb318ffe6a10748bced949bdd35f7b087e2a05f0#writeContract#F2)**
* similar to above, but use cbETH. You must approve Baseloop to spend your cbETH
* `leverageMultiplier` is relative to the input `cbETH` amount


**[close](https://basescan.org/address/0xdb318ffe6a10748bced949bdd35f7b087e2a05f0#writeContract#F1)**
* Fully unwind your leveraged position
* *optionally* provide some ETH to repay a portion of the loan

## Developers

*requires [foundry](https://book.getfoundry.sh/)*

Currently deployed to: [0xDB318ffe6A10748BCeD949bdd35F7B087e2A05F0](https://basescan.org/address/0xdb318ffe6a10748bced949bdd35f7b087e2a05f0)


Install & test:
```bash
forge install
forge test --rpc-url https://mainnet.base.org
```

Deploy:
```bash
# create .env containing
ETH_RPC_URL="https://mainnet.base.org"
ETHERSCAN_API_KEY=YOUR_API_KEY
ETH_GAS_PRICE=180000000 # 0.180 Gwei, update to market prices
ETH_PRIORITY_GAS_PRICE=900000 # 0.0009 Gwei, update to market prices
VERIFIER_URL="https://api.basescan.org/api"
CHAIN=8453
```

```bash
# activate environment variables
source .env

# Deploy Baseloop.sol
forge create src/Baseloop.sol:Baseloop --verify --interactive

# Allow Baseloop.sol to manage your Compound balances
cast send 0x46e6b214b524310239732D51387075E0e70970bf "allow(address,bool)" 0xBASELOOP_ADDR true --rpc-url https://mainnet.base.org --interactive
```
