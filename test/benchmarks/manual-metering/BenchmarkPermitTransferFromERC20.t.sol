pragma solidity ^0.8.9;

import "../BenchmarkBase.t.sol";


contract ManualBenchmarkPermitTransferFromERC20 is BenchmarkBase {
    function testBenchmarkPermitTransferFromERC20_x1000() public manuallyMetered {
        _runBenchmarkPermitTransferFromERC20(true, 1000, "Permit Transfer From ERC20");
    }

    function testBenchmarkPermitTransferFromWithAddtionalDataStringERC20_x1000() public manuallyMetered {
        _runBenchmarkPermitTransferFromWithAdditionalDataStringERC20(true, 1000, "Permit Transfer From With Additional Data String ERC20");
    }
}
