// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "../src/FlashLoan.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FlashLoanTest is Test {
    uint256 mainnetFork;
    SimpleFlashLoan flashLoan;
    IPoolAddressesProvider public addressProvider =
        IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
    ISwapRouter public swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public tokenB = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address public tokenA = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
    uint24 public poolFee = 100;
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    string public MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        // uint256 forkBlock = vm.envUint("FORK_BLOCK");
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        //  if (forkBlock != 0) vm.rollFork(forkBlock);
        deal(address(this), 100 ether);
        flashLoan = new SimpleFlashLoan(
            address(addressProvider),
            swapRouter,
            poolFee,
            nonfungiblePositionManager
        );
    }

    function testFlashLoanAndSwap() public {
        // Fetch the decimals for tokenA and tokenB
        uint8 decimalsA = ERC20(tokenA).decimals();
        uint8 decimalsB = ERC20(tokenB).decimals();

        // Calculate the flash loan amount and minting amounts based on decimals
        uint256 flashLoanAmount = 1_000_000 * (10 ** decimalsB);
        uint256 amount0ToMint = 1 * (10 ** decimalsA);
        uint256 amount1ToMint = 1 * (10 ** decimalsB);

        // Provide some USDC to the contract for loan repayment
        deal(tokenB, address(flashLoan), flashLoanAmount);

        uint256 initialBalanceA = IERC20(tokenA).balanceOf(address(flashLoan));
        uint256 initialBalanceB = IERC20(tokenB).balanceOf(address(flashLoan));

        // Request flash loan and perform the swap, passing the minting amounts
        flashLoan.requestFlashLoan(tokenA, tokenB, 5 * (10 ** decimalsB), amount0ToMint, amount1ToMint);

        uint256 finalBalanceA = IERC20(tokenA).balanceOf(address(flashLoan));
        uint256 finalBalanceB = IERC20(tokenB).balanceOf(address(flashLoan));

        assertLt(finalBalanceB, initialBalanceB, "Loan not repaid");
        assertGt(finalBalanceA, initialBalanceA, "No token received from swap");

        (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager
            .positions(flashLoan.tokenId());
        assertGt(liquidity, 0, "Liquidity not added to the pool");
    }
}
