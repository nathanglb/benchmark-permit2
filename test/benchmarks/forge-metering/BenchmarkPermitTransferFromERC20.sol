pragma solidity ^0.8.9;

import "../BenchmarkBase.t.sol";


contract ForgeBenchmarkPermitTransferFromERC20 is BenchmarkBase {
    function testBenchmarkPermitTransferFromERC20_x1000() public metered {
        _runBenchmarkPermitTransferFromERC20(false, 1000);
    }
}
