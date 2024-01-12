pragma solidity ^0.8.9;

import "../BenchmarkBase.t.sol";


contract ManualBenchmarkApprovedTransferERC20 is BenchmarkBase {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(alice);
        permit2.approve(
            address(token20),
            address(operator),
            uint160(USER_STARTING_BALANCE),
            uint48(block.timestamp + 100000)
        );

    }

    function testBenchmarkApprovedTransferFromERC20_x1000() public manuallyMetered {
        _runBenchmarkApprovedTransferFromERC20(true, 1000, "Approved Transfer From ERC20");
    }
}
