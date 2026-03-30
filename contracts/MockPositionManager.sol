// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract MockPositionManager {

    uint256 private _nextTokenId = 1;

    struct Position {
        address owner;
        address token0;
        address token1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint256 amount0;
        uint256 amount1;
    }

    mapping(uint256 => Position) public positions;

    event PositionMinted(
        uint256 indexed tokenId,
        address indexed owner,
        address token0,
        address token1,
        uint128 liquidity
    );

    event PoolCreated(
        address token0,
        address token1,
        uint24 fee,
        address pool
    );

    struct MintParams {
        address token0;
        address token1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(block.timestamp <= params.deadline, "Expired");

        // Pull tokens from caller (the proxy)
        IERC20(params.token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        IERC20(params.token1).transferFrom(msg.sender, address(this), params.amount1Desired);

        tokenId = _nextTokenId++;
        liquidity = uint128(params.amount0Desired + params.amount1Desired);
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        positions[tokenId] = Position({
            owner:     params.recipient,
            token0:    params.token0,
            token1:    params.token1,
            fee:       params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            amount0:   amount0,
            amount1:   amount1
        });

        emit PositionMinted(tokenId, params.recipient, params.token0, params.token1, liquidity);
    }

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 /* sqrtPriceX96 */
    ) external payable returns (address pool) {
        // Return a deterministic fake pool address
        pool = address(uint160(uint256(keccak256(abi.encodePacked(token0, token1, fee)))));
        emit PoolCreated(token0, token1, fee, pool);
    }
}
