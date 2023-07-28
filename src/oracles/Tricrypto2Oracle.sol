// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";
import "interfaces/IERC4626.sol";
import "interfaces/IOracle.sol";
import "interfaces/IGmxGlpManager.sol";
import "OpenZeppelin/utils/math/Math.sol";

interface Tricrypto {
    function virtual_price() external view returns (uint256);

    function price_oracle(uint256 k) external view returns (uint256);

    function A() external view returns (uint256);

    function gamma() external view returns (uint256);
}

contract Tricrypto2Oracle is IOracle {
    address immutable POOL;
    uint256 constant GAMMA0 = 28000000000000; // 2.8e-5;
    uint256 constant A0 = 2 * 3 ** 3 * 10000;
    uint256 constant DISCOUNT0 = 1087460000000000; // 0.00108..

    constructor(address pool) {
        POOL = pool;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function cubic_root(uint256 x) private pure returns (uint256) {
        // x is taken at base 1e36
        // result is at base 1e18
        // Will have convergence problems when ETH*BTC is cheaper than 0.01 squared dollar
        // (for example, when BTC < $0.1 and ETH < $0.1)
        uint256 D = x / 10 ** 18;
        for (uint256 i = 0; i < 255; i++) {
            uint256 diff = 0;
            uint256 D_prev = D;
            D = (D * (2 * 10 ** 18 + ((((x / D) * 10 ** 18) / D) * 10 ** 18) / D)) / (3 * 10 ** 18);
            if (D > D_prev) {
                diff = D - D_prev;
            } else {
                diff = D_prev - D;
            }
            if (diff <= 1 || diff * 10 ** 18 < D) return D;
        }
        revert("Did not converge");
    }

    function _get() internal view returns (uint256) {
        uint256 vp = Tricrypto(POOL).virtual_price();
        uint256 p1 = Tricrypto(POOL).price_oracle(0);
        uint256 p2 = Tricrypto(POOL).price_oracle(1);

        uint256 max_price = (3 * vp * cubic_root(p1 * p2)) / 10 ** 18;

        // ((A/A0) * (gamma/gamma0)**2) ** (1/3)
        uint256 g = (Tricrypto(POOL).gamma() * 10 ** 18) / GAMMA0;
        uint256 a = (Tricrypto(POOL).A() * 10 ** 18) / A0;
        uint256 discount = Math.max((g ** 2 / 10 ** 18) * a, 10 ** 34); // handle qbrt nonconvergence
        // if discount is small, we take an upper bound
        discount = (cubic_root(discount) * DISCOUNT0) / 10 ** 18;

        max_price -= (max_price * discount) / 10 ** 18;
        return 1e36 / max_price;
    }

    // Get the latest exchange rate
    /// @inheritdoc IOracle
    function get(bytes calldata) public view override returns (bool, uint256) {
        return (true, _get());
    }

    // Check the last exchange rate without any state changes
    /// @inheritdoc IOracle
    function peek(bytes calldata) public view override returns (bool, uint256) {
        return (true, _get());
    }

    // Check the current spot exchange rate without any state changes
    /// @inheritdoc IOracle
    function peekSpot(bytes calldata data) external view override returns (uint256 rate) {
        (, rate) = peek(data);
    }

    /// @inheritdoc IOracle
    function name(bytes calldata) public pure override returns (string memory) {
        return "Tricrypto USD Oracle";
    }

    /// @inheritdoc IOracle
    function symbol(bytes calldata) public pure override returns (string memory) {
        return "Tricrypto/USD";
    }
}
