## Version 20241221

### Mechanism changes:

- To ensure non-winning token holders able to convert their tokens to the winning token at a fair rate, the calculation and fee assessment for burning a non-winning token in exchange for winning token (after the winning token is published to Uniswap) is changed. The new mechanism addresses the problem that previously, non-winning token holders are only able to acquire the winning token (through burn-and-convert) at close to the highest price of the winning token, even the majority of the holders of the winning token already sold off their holdings on Uniswap. 
  - Fee is now only assessed once instead of twice from the conversion transaction.
  - The conversion rate is now based on the time-weighted average price over the last 120 seconds at the published pool on Uniswap, instead of based on the bonding curve of the winning token.
    - Specifically, first, the user's non-winning token is converted to native token (ONE) based on the bonding curve of the non-winning token
    - Then, a standard fee is deducted from the conversion. The amount is same as transactions for buying or selling tokens when a competition is still active
    - After that, the remaining native token is converted to the winning token, based on the current price at Uniswap.
    - If less than 120 seconds have elapsed since the pool was created, or at least 60 swaps have been executed on Uniswap, the conversion will fail.

### Interface changes:

- Changed event structure `BurnTokenAndMintWinner`, removed a field that represents converted native token amount, added a field showing fees deducted
- Removed `claimFee()` function, which clears fee accumulator. Fees can only be withdrawn using `withdrawFee()` which does not reset statistics
- Changed `fee` public field to `feeAccumulated`

### Internal changes:

- Added function `getMintAmountPostPublish` to calculate the amount of tokens that should be minted based on Uniswap pool price, given the collateral amount. It reverts if the pool does not exist
- Added helper function `getSqrtPriceX96` to obtain current time-weighted average price from the Uniswap pool of the token
- Miscellaneous improvements on function mutability