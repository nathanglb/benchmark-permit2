pragma solidity ^0.8.9;

import "../BenchmarkBase.t.sol";


contract ForgeBenchmarkCancelNonce is BenchmarkBase {
    function testCancelNonce_x1000() public metered {
        _runBenchmarkCancelNonce(false, 1000, "Cancel Nonce");
    }
}
