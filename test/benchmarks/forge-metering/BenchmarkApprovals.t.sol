pragma solidity ^0.8.9;

import "../BenchmarkBase.t.sol";


contract ForgeBenchmarkApprove is BenchmarkBase {
    function testApproveERC20_x1000() public metered {
        _runBenchmarkApproveERC20(false, 1000, "Approve ERC20");
    }

    function testSignatureApproveERC20_x1000() public metered {
        _runBenchmarkSignatureApproveERC20(false, 1000, "Signature Approve ERC20");
    }
}
