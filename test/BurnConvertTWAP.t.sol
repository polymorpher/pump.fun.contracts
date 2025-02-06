// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@contracts/TokenFactory.sol";
import "@contracts/BancorBondingCurve.sol";
import "@contracts/Token.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract BurnConvertTWAPTest is Test {
    TokenFactory internal tf;
    BancorBondingCurve internal bc;
    uint256 internal FEE_PERCENT = vm.envUint("FEE_PERCENT");
    uint256 internal SLOPE_SCALED = vm.envUint("SLOPE_SCALED");
    uint32 internal WEIGHT_SCALED = uint32(vm.envUint("WEIGHT_SCALED"));
    address internal UNISWAP_V3_FACTORY = vm.envAddress("UNISWAP_V3_FACTORY");
    address internal UNISWAP_V3_NPM = vm.envAddress("UNISWAP_V3_NPM");
    address internal WETH = vm.envAddress("WETH");
    Token internal winnerToken;
    Token internal loserToken;

    address Owner = address(0x1234);
    address Alice = address(0x1235);
    address Bob = address(0x1236);
    address Charlie = address(0x1237);

    event BurnTokenAndMintWinner(
        address indexed sender,
        address indexed token,
        address indexed winnerToken,
        uint256 burnedAmount,
        uint256 mintedAmount,
        uint256 fee,
        uint256 timestamp
    );

    event WinnerLiquidityAdded(
        address indexed tokenAddress,
        address indexed tokenCreator,
        address indexed pool,
        address sender,
        uint256 tokenId,
        uint128 liquidity,
        uint256 actualTokenAmount,
        uint256 actualAssetAmount,
        uint256 timestamp
    );

    function setUp() public {
        vm.deal(Alice, 100 ether);
        vm.deal(Bob, 100 ether);
        vm.deal(Charlie, 100 ether);
        Token tref = new Token();
        vm.startPrank(Owner);
        vm.deal(Owner, 1000 ether);

        bc = new BancorBondingCurve(SLOPE_SCALED, WEIGHT_SCALED);
        tf = new TokenFactory(address(tref), UNISWAP_V3_FACTORY, UNISWAP_V3_NPM, address(bc), WETH, FEE_PERCENT);
        vm.stopPrank();

        vm.startPrank(Alice);
        winnerToken = tf.createToken("winner", "WIN", "https://winner.local");
        tf.buy{value: 2 ether}(address(winnerToken));
        vm.stopPrank();

        vm.startPrank(Bob);
        loserToken = tf.createToken("loser", "LOSE", "https://loser.local");
        tf.buy{value: 1 ether}(address(loserToken));
        vm.stopPrank();
    }

    function test_getTwapSqrtPriceX96_normalCase() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);
        tf.publishToUniswap(address(winnerToken));
        
        // Wait for sufficient observations
        vm.warp(block.timestamp + 120);
        
        uint160 twapPrice = tf.getTwapSqrtPriceX96(address(winnerToken), 120);
        assertGt(twapPrice, 0, "TWAP price should be greater than 0");
        vm.stopPrank();
    }

    function test_getTwapSqrtPriceX96_poolTooNew() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);
        tf.publishToUniswap(address(winnerToken));
        
        // Try to get TWAP immediately after pool creation
        vm.expectRevert(abi.encodeWithSignature("PoolTooNew()"));
        tf.getTwapSqrtPriceX96(address(winnerToken), 120);
        vm.stopPrank();
    }

    function test_getTwapSqrtPriceX96_nonExistentPool() public {
        vm.startPrank(Owner);
        vm.expectRevert(abi.encodeWithSignature("PoolNonExist()"));
        tf.getTwapSqrtPriceX96(address(winnerToken), 120);
        vm.stopPrank();
    }

    function test_getTwapSqrtPriceX96_insufficientObservations() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);
        tf.publishToUniswap(address(winnerToken));
        
        // Add some observations but less than required
        for (uint i = 0; i < 30; i++) {
            vm.warp(block.timestamp + 1);
            vm.prank(Alice);
            tf.buy{value: 0.1 ether}(address(winnerToken));
        }
        
        vm.expectRevert(abi.encodeWithSignature("PoolTooNew()"));
        tf.getTwapSqrtPriceX96(address(winnerToken), 120);
        vm.stopPrank();
    }

    function test_getTwapSqrtPriceX96_priceCalculation() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);
        tf.publishToUniswap(address(winnerToken));
        
        // Wait and generate sufficient observations
        for (uint i = 0; i < 60; i++) {
            vm.warp(block.timestamp + 2);
            vm.prank(Alice);
            tf.buy{value: 0.1 ether}(address(winnerToken));
        }
        
        uint160 twapPrice1 = tf.getTwapSqrtPriceX96(address(winnerToken), 120);
        
        // Price should increase after more buys
        vm.prank(Bob);
        tf.buy{value: 1 ether}(address(winnerToken));
        
        uint160 twapPrice2 = tf.getTwapSqrtPriceX96(address(winnerToken), 120);
        assertGt(twapPrice2, twapPrice1, "TWAP price should increase after buys");
        vm.stopPrank();
    }

    function test_burnTokenAndMintWinner_singleFee() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);
        tf.publishToUniswap(address(winnerToken));

        // Generate sufficient observations
        for (uint i = 0; i < 60; i++) {
            vm.warp(block.timestamp + 2);
            vm.prank(Alice);
            tf.buy{value: 0.1 ether}(address(winnerToken));
        }
        vm.stopPrank();

        vm.startPrank(Bob);
        uint256 loserBalance = loserToken.balanceOf(Bob);
        uint256 feeAccumulatedBefore = tf.feeAccumulated();
        
        tf.burnTokenAndMintWinner(address(loserToken));
        
        uint256 feeAccumulatedAfter = tf.feeAccumulated();
        uint256 feePaid = feeAccumulatedAfter - feeAccumulatedBefore;
        uint256 expectedFee = (loserBalance * tf.feePercent()) / tf.FEE_DENOMINATOR();
        assertEq(feePaid, expectedFee, "Single fee should be assessed");
        vm.stopPrank();
    }

    function test_burnTokenAndMintWinner_conversionRate() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);
        tf.publishToUniswap(address(winnerToken));

        // Generate sufficient observations
        for (uint i = 0; i < 60; i++) {
            vm.warp(block.timestamp + 2);
            vm.prank(Alice);
            tf.buy{value: 0.1 ether}(address(winnerToken));
        }
        vm.stopPrank();

        vm.startPrank(Bob);
        uint256 loserBalance = loserToken.balanceOf(Bob);
        uint256 winnerBalanceBefore = winnerToken.balanceOf(Bob);
        
        tf.burnTokenAndMintWinner(address(loserToken));
        
        uint256 winnerBalanceAfter = winnerToken.balanceOf(Bob);
        uint256 winnerReceived = winnerBalanceAfter - winnerBalanceBefore;
        
        uint256 expectedWinnerAmount = tf.getMintAmountPostPublish(
            tf._sellReceivedAmount(address(loserToken), loserBalance),
            address(winnerToken)
        );
        assertEq(winnerReceived, expectedWinnerAmount, "Conversion rate should match TWAP");
        vm.stopPrank();
    }

    function test_burnTokenAndMintWinner_failsForWinner() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);
        tf.publishToUniswap(address(winnerToken));
        vm.stopPrank();

        vm.startPrank(Alice);
        vm.expectRevert("Token address is winner");
        tf.burnTokenAndMintWinner(address(winnerToken));
        vm.stopPrank();
    }

    function test_burnTokenAndMintWinner_failsForActiveCompetition() public {
        vm.startPrank(Alice);
        vm.expectRevert("The competition is still active");
        tf.burnTokenAndMintWinner(address(loserToken));
        vm.stopPrank();
    }

    function test_publishToUniswap_initialLiquidity() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);

        uint256 winnerCollateral = tf.collateralById(1, address(winnerToken));
        uint256 loserCollateral = tf.collateralById(1, address(loserToken));
        uint256 totalCollateral = tf.getCollateralByCompetitionId(1);

        tf.publishToUniswap(address(winnerToken));
        address pool = tf.tokensPools(address(winnerToken));
        
        uint128 initialLiquidity = IUniswapV3Pool(pool).liquidity();
        assertGt(initialLiquidity, 0, "Initial liquidity should be greater than 0");
        
        uint256 poolWethBalance = IERC20(WETH).balanceOf(pool);
        assertEq(poolWethBalance, winnerCollateral, "Only winner collateral should be added initially");
        vm.stopPrank();
    }

    function test_burnTokenAndMintWinner_incrementalLiquidity() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);
        tf.publishToUniswap(address(winnerToken));

        // Generate sufficient observations
        for (uint i = 0; i < 60; i++) {
            vm.warp(block.timestamp + 2);
            vm.prank(Alice);
            tf.buy{value: 0.1 ether}(address(winnerToken));
        }
        
        address pool = tf.tokensPools(address(winnerToken));
        uint128 liquidityBefore = IUniswapV3Pool(pool).liquidity();
        vm.stopPrank();

        vm.startPrank(Bob);
        uint256 loserBalance = loserToken.balanceOf(Bob);
        uint256 expectedEth = tf._sellReceivedAmount(address(loserToken), loserBalance);
        uint256 expectedTokens = tf.getMintAmountPostPublish(expectedEth, address(winnerToken));
        
        tf.burnTokenAndMintWinner(address(loserToken));
        
        uint128 liquidityAfter = IUniswapV3Pool(pool).liquidity();
        assertGt(liquidityAfter, liquidityBefore, "Liquidity should increase after burn and convert");
        
        uint256 bobWinnerBalance = winnerToken.balanceOf(Bob);
        assertEq(bobWinnerBalance, expectedTokens, "Bob should receive correct amount of winner tokens");
        
        uint256 factoryWinnerBalance = winnerToken.balanceOf(address(tf));
        assertEq(factoryWinnerBalance, 0, "Factory should not hold winner tokens after adding liquidity");
        vm.stopPrank();
    }

    function test_getMintAmountPostPublish_overflow() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);
        tf.publishToUniswap(address(winnerToken));

        // Generate sufficient observations with high price
        for (uint i = 0; i < 60; i++) {
            vm.warp(block.timestamp + 2);
            vm.prank(Alice);
            tf.buy{value: 10 ether}(address(winnerToken));
        }

        // Test both token orderings (token < WETH and token > WETH)
        uint256 amount = tf.getMintAmountPostPublish(1 ether, address(winnerToken));
        assertGt(amount, 0, "Should handle high prices without overflow");

        // Create a token with address greater than WETH to test other branch
        Token highAddressToken = new Token();
        require(address(highAddressToken) > WETH, "Test setup failed: token address not greater than WETH");
        amount = tf.getMintAmountPostPublish(1 ether, address(highAddressToken));
        assertGt(amount, 0, "Should handle high prices without overflow for token > WETH");
        vm.stopPrank();
    }

    function test_poolInitialization_failures() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);

        // Test non-existent pool
        vm.expectRevert(abi.encodeWithSignature("PoolNonExist()"));
        tf.getTwapSqrtPriceX96(address(0x1234), 120);

        // Test pool too new
        tf.publishToUniswap(address(winnerToken));
        vm.expectRevert(abi.encodeWithSignature("PoolTooNew()"));
        tf.getTwapSqrtPriceX96(address(winnerToken), 120);
        vm.stopPrank();
    }

    function test_invalidTokenAddresses() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);

        // Test zero address
        vm.expectRevert();
        tf.publishToUniswap(address(0));

        // Test non-token address
        vm.expectRevert();
        tf.publishToUniswap(address(0x1234));

        // Test non-winner token
        vm.expectRevert("Token address not winner");
        tf.publishToUniswap(address(loserToken));
        vm.stopPrank();
    }

    function test_burnTokenAndMintWinner_equalTokenMinting() public {
        vm.startPrank(Owner);
        tf.startNewCompetition();
        tf.setWinnerByCompetitionId(1);
        tf.publishToUniswap(address(winnerToken));

        // Generate sufficient observations
        for (uint i = 0; i < 60; i++) {
            vm.warp(block.timestamp + 2);
            vm.prank(Alice);
            tf.buy{value: 0.1 ether}(address(winnerToken));
        }
        vm.stopPrank();

        vm.startPrank(Bob);
        uint256 bobWinnerBalanceBefore = winnerToken.balanceOf(Bob);
        uint256 poolLiquidityBefore = IUniswapV3Pool(tf.tokensPools(address(winnerToken))).liquidity();
        
        tf.burnTokenAndMintWinner(address(loserToken));
        
        uint256 bobWinnerBalanceAfter = winnerToken.balanceOf(Bob);
        uint256 poolLiquidityAfter = IUniswapV3Pool(tf.tokensPools(address(winnerToken))).liquidity();
        
        uint256 bobTokensReceived = bobWinnerBalanceAfter - bobWinnerBalanceBefore;
        assertGt(bobTokensReceived, 0, "Bob should receive winner tokens");
        assertGt(poolLiquidityAfter, poolLiquidityBefore, "Pool liquidity should increase");
        
        // Verify equal token minting by checking pool liquidity increase matches user token increase
        uint256 poolTokenIncrease = uint256(poolLiquidityAfter - poolLiquidityBefore);
        assertApproxEqRel(bobTokensReceived, poolTokenIncrease, 0.01e18, "Pool and user should receive equal tokens");
        vm.stopPrank();
    }
}
