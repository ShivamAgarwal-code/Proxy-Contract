// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============================================================
//  Interfaces
// ============================================================

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface INonfungiblePositionManager {
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
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);
}

// ============================================================
//  Implementation — UniswapPositionManager (logic contract)
// ============================================================

contract UniswapPositionManager {

    // --- storage (shared with proxy via delegatecall) --------
    address public owner;
    address public positionManager;  // Uniswap V3 NonfungiblePositionManager
    address public weth;             // WETH address
    bool    private _initialized;

    // --- events ----------------------------------------------
    event PositionCreated(
        address indexed user,
        uint256 tokenId,
        address tokenA
    );
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    // --- modifiers -------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // --- initializer (called once through proxy) -------------
    function initialize(
        address _positionManager,
        address _weth,
        address _owner
    ) external {
        require(!_initialized, "Already initialized");
        _initialized = true;
        positionManager = _positionManager;
        weth = _weth;
        owner = _owner;
    }

    // --- core: deposit Asset A + ETH → Uniswap V3 position --
    /// @notice Deposit ERC20 (tokenA) + ETH and open a Uniswap V3 position.
    function createPosition(
        address tokenA,
        uint256 amountA,
        uint24  fee,
        int24   tickLower,
        int24   tickUpper,
        uint160 sqrtPriceX96
    ) external payable returns (uint256 tokenId) {
        require(msg.value > 0, "Must send ETH");
        require(amountA > 0, "Must deposit tokenA");

        // 1. Pull tokenA from caller
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);

        // 2. Wrap ETH → WETH
        IWETH(weth).deposit{value: msg.value}();

        // 3. Sort tokens (Uniswap requires token0 < token1)
        bool tokenAIsToken0 = tokenA < weth;
        address token0 = tokenAIsToken0 ? tokenA : weth;
        address token1 = tokenAIsToken0 ? weth : tokenA;
        uint256 amount0 = tokenAIsToken0 ? amountA : msg.value;
        uint256 amount1 = tokenAIsToken0 ? msg.value : amountA;

        // 4. Optionally create & initialize pool
        if (sqrtPriceX96 > 0) {
            INonfungiblePositionManager(positionManager)
                .createAndInitializePoolIfNecessary(token0, token1, fee, sqrtPriceX96);
        }

        // 5. Approve & mint
        IERC20(token0).approve(positionManager, amount0);
        IERC20(token1).approve(positionManager, amount1);

        tokenId = _mintAndRefund(token0, token1, fee, tickLower, tickUpper, amount0, amount1);

        emit PositionCreated(msg.sender, tokenId, tokenA);
    }

    function _mintAndRefund(
        address token0,
        address token1,
        uint24  fee,
        int24   tickLower,
        int24   tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 tokenId) {
        uint256 used0;
        uint256 used1;
        (tokenId, , used0, used1) = INonfungiblePositionManager(positionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0:         token0,
                token1:         token1,
                fee:            fee,
                tickLower:      tickLower,
                tickUpper:      tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min:     0,
                amount1Min:     0,
                recipient:      msg.sender,
                deadline:       block.timestamp + 300
            })
        );

        // Refund unused tokens
        if (used0 < amount0) {
            IERC20(token0).transfer(msg.sender, amount0 - used0);
        }
        if (used1 < amount1) {
            IERC20(token1).transfer(msg.sender, amount1 - used1);
        }
    }

    // --- admin: recover stuck tokens -------------------------
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "ETH transfer failed");
        emit Withdrawn(address(0), to, amount);
    }

    receive() external payable {}
}


// ============================================================
//  Proxy — minimal ERC-1967 proxy
// ============================================================

contract UniswapPositionProxy {

    // ERC-1967 implementation slot
    bytes32 private constant _IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // ERC-1967 admin slot
    bytes32 private constant _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    event Upgraded(address indexed implementation);

    constructor(address impl, bytes memory initData) {
        _setAdmin(msg.sender);
        _setImplementation(impl);
        if (initData.length > 0) {
            (bool ok, ) = impl.delegatecall(initData);
            require(ok, "Init failed");
        }
    }

    /// @notice Upgrade to a new implementation (admin only).
    function upgradeTo(address newImpl) external {
        require(msg.sender == _getAdmin(), "Not admin");
        _setImplementation(newImpl);
        emit Upgraded(newImpl);
    }

    /// @notice Returns current implementation address.
    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /// @notice Returns proxy admin address.
    function admin() external view returns (address) {
        return _getAdmin();
    }

    // --- fallback: delegatecall to implementation ------------
    fallback() external payable {
        address impl = _getImplementation();
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}

    // --- internal helpers ------------------------------------
    function _setImplementation(address impl) private {
        bytes32 slot = _IMPL_SLOT;
        assembly { sstore(slot, impl) }
    }

    function _getImplementation() private view returns (address impl) {
        bytes32 slot = _IMPL_SLOT;
        assembly { impl := sload(slot) }
    }

    function _setAdmin(address adm) private {
        bytes32 slot = _ADMIN_SLOT;
        assembly { sstore(slot, adm) }
    }

    function _getAdmin() private view returns (address adm) {
        bytes32 slot = _ADMIN_SLOT;
        assembly { adm := sload(slot) }
    }
}
