## *baseloop* 🔵🔁

*One-click leverage on cbETH (up to 10x!!!) with Compound III on Base*

---

Gas efficient with minimal "trips":
1. Flash loan cbETH from Aave V3
2. Supply (collateralize) cbETH on Compound III
3. Borrow ETH on Compound III
4. Swap ETH for cbETH on Uniswap V3
5. Repay the flash loan

---

## Usage

### The one-click leverage does not have an UI. You will need to use *basescan*

* [cbETH APY Calculator](https://docs.google.com/spreadsheets/d/1mLf3QrqNqqyDjQtOqL1UxRTSkgItmWxmjMAqI8ppAnw)
* [Basescan contract](https://basescan.org/address/0xD342096DC2271efE68E63aF4F5EBf5A6C9cB9Ee9)


> Note: You must allow Baseloop to manage your Compound balances
> ```bash
> cast send 0x46e6b214b524310239732D51387075E0e70970bf "allow(address,bool)" 0xD342096DC2271efE68E63aF4F5EBf5A6C9cB9Ee9 true --rpc-url https://mainnet.base.org --interactive
> ```

Docs:

**[adjustPosition](https://basescan.org/address/0xD342096DC2271efE68E63aF4F5EBf5A6C9cB9Ee9#writeContract#F1)**

Adjust your position up or down

    - payableAmount: an amount of Ether to leverage on. Optional when modifying existing leverage

    - targetCollateraValue: the total desired amount of collateral value in Ether. Multiple payableAmount by leverage multiplier to get this number. Expressed with 18 decimals. 2.5e18 = 2.5 ether of total collateral value, 2500000000000000000

    - collateralFactor: desired collateral factor (or "loan-to-value"). Expressed with 18 decimals. 0.8e18 = 80% collateral factor, 800000000000000000

**[adjustPositionCBETH](https://basescan.org/address/0xD342096DC2271efE68E63aF4F5EBf5A6C9cB9Ee9#writeContract#F2)**

Leverage up using cbETH tokens (cannot deleverage with this function)

    - cbETHAmount: an amount of cbETH to leverage on

    - targetCollateral: the total desired amount of cbETH (as collateral on Compound). Expressed with 18 decimals. 2.5e18 = 2.5 cbETH of total collateral, 2500000000000000000

    - collateralFactor: desired collateral factor (or "loan-to-value"). Expressed with 18 decimals. 0.8e18 = 80% collateral factor, 800000000000000000


**[close](https://basescan.org/address/0xD342096DC2271efE68E63aF4F5EBf5A6C9cB9Ee9#writeContract#F3)**
* Fully unwind your leveraged position
* *optionally* provide some ETH to repay a portion of the loan

## Developers

*requires [foundry](https://book.getfoundry.sh/)*

Currently deployed to: [0xD342096DC2271efE68E63aF4F5EBf5A6C9cB9Ee9](https://basescan.org/address/0xD342096DC2271efE68E63aF4F5EBf5A6C9cB9Ee9)


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