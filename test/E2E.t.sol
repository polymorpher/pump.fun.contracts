pragma solidity >=0.8.26;

import "forge-std/Test.sol";
import "@contracts/TokenFactory.sol";
import "@contracts/BancorBondingCurve.sol";
import "@contracts/Token.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract E2ETest is Test {
    TokenFactory internal tf;
    BancorBondingCurve internal bc;
    uint256 internal FEE_PERCENT = vm.envUint("FEE_PERCENT");
    uint256 internal SLOPE_SCALED = vm.envUint("SLOPE_SCALED");
    uint32 internal WEIGHT_SCALED = uint32(vm.envUint("WEIGHT_SCALED"));
    address internal UNISWAP_V3_FACTORY = vm.envAddress("UNISWAP_V3_FACTORY");
    address internal UNISWAP_V3_NPM = vm.envAddress("UNISWAP_V3_NPM");
    address internal WETH = vm.envAddress("WETH");
    Token internal ta;
    Token internal tb;
    Token internal tc;

    address Owner = address(0x1234);
    address Alice = address(0x1235);
    address Bob = address(0x1236);
    address Charlie = address(0x1237);
    address Dave = address(0x1238);
    address Server = address(0x1239);

    event BurnTokenAndMintWinner(
        address indexed sender,
        address indexed token,
        address indexed winnerToken,
        uint256 burnedAmount,
        uint256 receivedETH,
        uint256 mintedAmount,
        uint256 timestamp
    );

    function setUp() public {
        vm.deal(Alice, 100 ether);
        vm.deal(Bob, 100 ether);
        vm.deal(Charlie, 100 ether);
        vm.deal(Dave, 1 ether);
        Token tref = new Token();
        vm.startPrank(Owner);
        vm.deal(Owner, 1000 ether);

        bc = new BancorBondingCurve(SLOPE_SCALED, WEIGHT_SCALED);
        tf = new TokenFactory(address(tref), UNISWAP_V3_FACTORY, UNISWAP_V3_NPM, address(bc), WETH, FEE_PERCENT);
        vm.stopPrank();

        vm.startPrank(Alice);
        ta = tf.createToken("a", "A", "https://a.local");
        tf.buy{value: 1 ether}(address(ta));
        vm.stopPrank();

        vm.startPrank(Bob);
        tb = tf.createToken("b", "B", "https://b.local");
        tf.buy{value: 1 ether}(address(tb));
        vm.stopPrank();

        vm.startPrank(Charlie);
        tc = tf.createToken("c", "C", "https://c.local");
        tf.buy{value: 1 ether}(address(tc));
        vm.stopPrank();
    }

    function test_publishToUniswap() public {
        vm.startPrank(Dave);
        uint256 taBalanceBefore = ta.balanceOf(Dave);
        uint256 calculatedReceiveAmountBefore = tf._buyReceivedAmount(address(ta), 0.1 ether);
        // buy
        tf.buy{value: 0.1 ether}(address(ta));

        uint256 taBalanceAfter = ta.balanceOf(Dave);
        assertApproxEqRel(calculatedReceiveAmountBefore, taBalanceAfter - taBalanceBefore, 0.0001 ether, "received amount wrong");

        uint256 calculatedReceiveAmountAfter = tf._buyReceivedAmount(address(ta), 0.1 ether);
        assertTrue(calculatedReceiveAmountAfter < calculatedReceiveAmountBefore, "the price has not increased");

        tf.buy{value: 0.1 ether}(address(ta));
        tf.buy{value: 0.05 ether}(address(tb));
        tf.buy{value: 0.02 ether}(address(tc));
        vm.stopPrank();

        vm.startPrank(Owner);
        tf.startNewCompetition();
        // check CompetitionId increased
        uint256 currentCompetitionId = tf.currentCompetitionId();
        assertEq(currentCompetitionId, 2, "currentCompetitionId not 2");
        vm.stopPrank();

        // user can't buy more token after startNewCompetition
        vm.startPrank(Dave);
        vm.expectRevert("The competition for this token has already ended");
        tf.buy{value: 0.1 ether}(address(ta));
        vm.expectRevert("The competition for this token has already ended");
        tf.buy{value: 0.1 ether}(address(tb));
        vm.expectRevert("The competition for this token has already ended");
        tf.buy{value: 0.1 ether}(address(tc));
        vm.stopPrank();

        vm.startPrank(Dave);
        vm.expectRevert("Token address is winner");
        tf.burnTokenAndMintWinner(address(ta));

        taBalanceBefore = ta.balanceOf(address(Dave));

        uint256 burnedAmount = tb.balanceOf(address(Dave));
        uint256 receivedETH = tf._sellReceivedAmount(address(tb), burnedAmount);
        uint256 mintedAmount = tf._buyReceivedAmount(address(ta), receivedETH);

        vm.expectEmit(true, true, true, true, address(tf));
        emit BurnTokenAndMintWinner(
            address(Dave), // sender
            address(tb), // token
            address(ta), // winnerToken
            burnedAmount,
            receivedETH,
            mintedAmount,
            block.timestamp
        );
        tf.burnTokenAndMintWinner(address(tb));

        taBalanceAfter = ta.balanceOf(address(Dave));
        assertEq(mintedAmount, taBalanceAfter - taBalanceBefore, "taBalance incorrect");
        vm.stopPrank();

        vm.startPrank(Server);
        vm.expectRevert('Token address not winner');
        tf.publishToUniswap(address(tb));

        vm.expectRevert('Token address not winner');
        tf.publishToUniswap(address(tc));

        address tokenPool = tf.tokensPools(address(ta));
        assertEq(tokenPool, address(0x0), 'Token pool address not 0x0');

        // calculate liquidity
        uint256 currentCollateral = tf.collateralById(currentCompetitionId - 1, address(ta));
        uint256 totalCollateralFromAllTokens = tf.getCollateralByCompetitionId(currentCompetitionId - 1);
        uint256 numTokensPerEther = bc.computeMintingAmountFromPrice(currentCollateral, ta.totalSupply(), 1 ether);
        uint256 mintAmount = (totalCollateralFromAllTokens * numTokensPerEther) / 1e18;

        tf.publishToUniswap(address(ta));

        tokenPool = tf.tokensPools(address(ta));
        assertNotEq(tokenPool, address(0x0), 'Token pool address is 0x0');

        uint128 liquidity = IUniswapV3Pool(tokenPool).liquidity();

        // TODO: check uniswap pool liquidity
        //assertEq(liquidity, totalCollateralFromAllTokens, 'Liquidity incorrect');

        vm.stopPrank();

        // TODO: check uniswap pool liquidity and price

        // // TODO: have alice to trade some tokens on uniswap

        // // TODO: have bob / charlie / dave to trade token ta on uniswap
    }
}
