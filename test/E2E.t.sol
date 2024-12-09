pragma solidity >=0.8.26;

import "forge-std/Test.sol";
import "@contracts/TokenFactory.sol";
import "@contracts/BancorBondingCurve.sol";
import "@contracts/Token.sol";

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
        tf.buy{value: 0.1 ether}(address(ta));
        // TODO: check price, token balance, ... after each buy
        tf.buy{value: 0.1 ether}(address(ta));
        tf.buy{value: 0.05 ether}(address(tb));
        tf.buy{value: 0.02 ether}(address(tc));
        vm.stopPrank();

        vm.startPrank(Owner);
        tf.startNewCompetition();
        // TODO: check fee, test withdraw fee
        vm.stopPrank();

        vm.startPrank(Server);
        vm.expectRevert();
        tf.publishToUniswap(address(tb));
        vm.expectRevert();
        tf.publishToUniswap(address(tc));
        // TODO: check event emission, token minting amount...
        tf.publishToUniswap(address(ta));
        vm.stopPrank();
        // TODO: check uniswap pool liquidity and price

        vm.startPrank(Bob);
        tf.burnTokenAndMintWinner(address(tb));
        // TODO: check event emission, token minting amount...
        vm.stopPrank();

        vm.startPrank(Charlie);
        tf.burnTokenAndMintWinner(address(tc));
        // TODO: check event emission, token minting amount...
        vm.stopPrank();

        vm.startPrank(Dave);
        tf.burnTokenAndMintWinner(address(tb));
        // TODO: check event emission, token minting amount...
        tf.burnTokenAndMintWinner(address(tc));
        // TODO: check event emission, token minting amount...
        vm.stopPrank();

        // TODO: have alice to trade some tokens on uniswap

        // TODO: have bob / charlie / dave to trade token ta on uniswap
    }
}
