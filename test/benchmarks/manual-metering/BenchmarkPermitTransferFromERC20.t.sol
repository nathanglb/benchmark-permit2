pragma solidity ^0.8.9;

import "../BenchmarkBase.t.sol";


contract ManualBenchmarkPermitTransferFromERC20 is BenchmarkBase {
    function testBenchmarkPermitTransferFromERC20_x1000() public manuallyMetered {
        _runBenchmarkPermitTransferFromERC20(true, 1000);
    }
}
