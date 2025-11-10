// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";

/**
 * @title Mock Shares Factory contract for testing
 * @author Cork Team
 */
contract MockSharesFactory {
    error MockSharesFactoryIsCalled();

    ///======================================================///
    ///================== CORE FUNCTIONS ====================///
    ///======================================================///

    function deployPoolShares(ISharesFactory.DeployParams calldata params) external pure returns (address principalToken, address swapToken) {
        revert MockSharesFactoryIsCalled();
    }
}
