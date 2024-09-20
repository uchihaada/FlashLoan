// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@demeter-protocol/contracts/e721-farms/uniswapV3/UniV3FarmDeployer.sol";
import "@demeter-protocol/contracts/e721-farms/uniswapV3/UniV3Farm.sol";
import "@demeter-protocol/contracts/Farm.sol";

contract SimpleFlashLoan is FlashLoanSimpleReceiverBase, IERC721Receiver {
    address payable owner;
    ISwapRouter public swapRouter;
    address public tokenA;
    address public tokenB;
    uint24 public poolFee;
    uint256 swapAmountOut;
    uint public tokenId;
    uint256 public amount0ToMint;
    uint256 public amount1ToMint;
    Farm public farm;
    UniV3FarmDeployer public farmDeployer;
    address public tokenAddress;
    address public tokenManager;
    INonfungiblePositionManager public nonfungiblePositionManager;
    uint256 public depositId;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    struct UniswapPoolData {
        address tokenA;
        address tokenB;
        uint24 feeTier;
        int24 tickLowerAllowed;
        int24 tickUpperAllowed;
    }

    struct RewardTokenData {
        address token;
        address tknManager;
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

    function requestFlashLoan(
        address _tokenA,
        address _tokenB,
        uint256 _amount,
        uint256 _amount0ToMint,
        uint256 _amount1ToMint
    ) public {
        tokenA = _tokenA;
        tokenB = _tokenB;
        amount0ToMint = _amount0ToMint;
        amount1ToMint = _amount1ToMint;
        POOL.flashLoanSimple(address(this), tokenB, _amount, "", 0);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // Swapping tokens
        swapAmountOut = swap(asset, tokenA, amount / 2);

        // Deposit both tokens into the Uniswap v3 pool
        (uint256 _tokenId, uint256 _liquidity) = depositInPool(
            tokenA,
            tokenB,
            amount / 2,
            swapAmountOut
        );

        // Creating a UniswapPoolData instance
        UniswapPoolData memory uniswapPoolData = UniswapPoolData({
            tokenA: tokenA,
            tokenB: tokenB,
            feeTier: poolFee,
            tickLowerAllowed: int24(-887272),
            tickUpperAllowed: int24(887272)
        });

        // Preparing reward data array
        RewardTokenData[] memory rewardData;
        rewardData[0] = RewardTokenData({
            token: tokenAddress,
            tknManager: tokenManager
        });
        rewardData[1] = RewardTokenData({
            token: address(0),
            tknManager: address(0)
        });

        // Calling createUniFarm
        address deployedFarm = createUniFarm(
            address(this),
            block.timestamp,
            block.timestamp + 300,
            uniswapPoolData,
            rewardData
        );
        depositInFarm(deployedFarm, _tokenId);

        //withdraw
        farm.withdraw(depositId);

        //withdraw from uniswap pool
        withdrawFromPool(_tokenId);

        // Repaying the flash loan
        uint256 totalAmount = amount + premium;
        IERC20(asset).approve(address(POOL), totalAmount);

        return true;
    }

    function createUniFarm(
        address _farmAdmin,
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        UniswapPoolData memory _uniswapPoolData,
        RewardTokenData[] memory _rewardData
    ) public returns (address) {
        address newFarm = farmDeployer.createFarm(
            UniV3FarmDeployer.FarmData({
                farmAdmin: _farmAdmin,
                farmStartTime: _farmStartTime,
                cooldownPeriod: _cooldownPeriod,
                uniswapPoolData: _uniswapPoolData,
                rewardData: _rewardData
            })
        );
        return newFarm;
    }

    function depositInFarm(address _farm, uint256 _tokenId) public {
        require(tokenId != 0, "No LP token to deposit");
        nonfungiblePositionManager.safeTransferFrom(
            address(this),
            address(_farm),
            _tokenId
        );
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

        // Remove allowance and refund excess tokens
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

    function withdrawFromPool(uint256 _tokenId) internal {
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory decreaseParams = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: _tokenId,
                    liquidity: deposits[_tokenId].liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager
            .decreaseLiquidity(decreaseParams);

        INonfungiblePositionManager.CollectParams
            memory collectParams = INonfungiblePositionManager.CollectParams({
                tokenId: _tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (
            uint256 collectedAmount0,
            uint256 collectedAmount1
        ) = nonfungiblePositionManager.collect(collectParams);

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
    ) external override returns (bytes4) {
        _createDeposit(operator, _tokenId);
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
