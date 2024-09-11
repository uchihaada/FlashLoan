// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "../src/FlashLoan.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FlashLoanTest is Test {
    uint256 mainnetFork;
    SimpleFlashLoan flashLoan;
    IPoolAddressesProvider public addressProvider =
        IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
    ISwapRouter public swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public tokenB = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public tokenA = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint24 public poolFee = 100;
    address public aaveLoanPool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    string public MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        deal(address(this), 100 ether);
        flashLoan = new SimpleFlashLoan(
            address(addressProvider),
            swapRouter,
            poolFee,
            nonfungiblePositionManager
        );
    }

    function testFlashLoanAndSwap() public {
        uint256 flashLoanAmount = 1 * 10 ** 18;

        //put some usdc in the contract to repay the interest
        deal(tokenA, address(flashLoan), flashLoanAmount);
        deal(tokenB, address(flashLoan), 1000000 * 10 ** 6);

        uint256 initialBalanceA = IERC20(tokenA).balanceOf(address(flashLoan));
        uint256 initialBalanceB = IERC20(tokenB).balanceOf(address(flashLoan));

        // taking the loan and swapping the token
        flashLoan.fn_RequestFlashLoan(tokenA, tokenB, 5 * 10 ** 6);

        // intiaal balance for the tokens
        uint256 finalBalanceA = IERC20(tokenA).balanceOf(address(flashLoan));
        uint256 finalBalanceB = IERC20(tokenB).balanceOf(address(flashLoan));

        assertLt(finalBalanceB, initialBalanceB, "Loan not repaid");
        assertGt(
            finalBalanceA,
            initialBalanceA,
            "Token B not received from swap"
        );

        (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager
            .positions(808380);
        assertGt(liquidity, 0, "Liquidity not added to the pool");
    }
}
