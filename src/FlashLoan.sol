// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
// import "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import "@aave/core-v3/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

// import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

// import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";

contract SimpleFlashLoan is FlashLoanSimpleReceiverBase {
    address payable owner;
    ISwapRouter public swapRouter;
    address public tokenA;
    address public tokenB;
    uint24 public poolFee;
    uint256 swapAmountOut;
    uint public tokenId;

    INonfungiblePositionManager public nonfungiblePositionManager;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }
    mapping(uint256 => Deposit) public deposits;

    constructor(
        address _addressProvider,
        ISwapRouter _router,
        uint24 _fee,
        INonfungiblePositionManager _nonfungiblePositionManager
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        swapRouter = _router;
        poolFee = _fee;
    }

    function fn_RequestFlashLoan(
        address _tokenA,
        address _tokenB,
        uint256 _amount
    ) public {
        tokenB = _tokenB;
        tokenA = _tokenA;
        POOL.flashLoanSimple(address(this), _tokenA, _amount, "", 0);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        //swapping tokens
        swapAmountOut = swap(asset, tokenB, amount / 2);
        //deposit both tokens in a v3 pool
        (uint256 _tokenId, uint256 _liquidity) = depositInPool(
            tokenA,
            tokenB,
            amount / 2,
            swapAmountOut
        );
        // Repaying the loan
        uint256 totalAmount = amount + premium;
        IERC20(asset).approve(address(POOL), totalAmount);

        return true;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function depositInPool(
        address _tokenA,
        address _tokenB,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 _tokenId, uint128 liquidity) {
        uint256 amount1ToMint = 1 * 1e18;
        uint256 amount0ToMint = 1 * 1e6;
        TransferHelper.safeApprove(
            _tokenA,
            address(nonfungiblePositionManager),
            amount0ToMint
        );
        TransferHelper.safeApprove(
            _tokenB,
            address(nonfungiblePositionManager),
            amount1ToMint
        );

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: _tokenA,
                token1: _tokenB,
                fee: poolFee,
                tickLower: int24(-887272),
                tickUpper: int24(887272),
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 60
            });

        (_tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager
            .mint(params);
        _createDeposit(msg.sender, _tokenId);

        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(
                _tokenA,
                address(nonfungiblePositionManager),
                0
            );
            uint refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(_tokenA, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(
                _tokenB,
                address(nonfungiblePositionManager),
                0
            );
            uint refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(_tokenB, msg.sender, refund1);
        }
        return (_tokenId, liquidity);
    }

    function _createDeposit(address _owner, uint256 _tokenId) internal {
        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(_tokenId);

        // set the owner and data for position
        // operator is msg.sender
        deposits[_tokenId] = Deposit({
            owner: _owner,
            liquidity: liquidity,
            token0: token0,
            token1: token1
        });

        tokenId = _tokenId;
    }

    function onERC721Received(
        address operator,
        address,
        uint256 _tokenId,
        bytes calldata
    ) external returns (bytes4) {
        // get position information
        _createDeposit(operator, _tokenId);

        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
