pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Permit2.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./mocks/ContractMock.sol";
import "./mocks/TestERC20.sol";

import "../utils/PermitSignature.sol";

import {MainnetMetering} from "forge-gas-metering/src/MainnetMetering.sol";


contract BenchmarkBase is MainnetMetering, Test, PermitSignature {
    struct TransferPermit {
        address token;
        uint256 id;
        uint256 amount;
        uint256 nonce;
        address operator;
        uint256 expiration;
        uint160 signerKey;
        address owner;
        address to;
    }

    struct GasMetrics {
        uint256 min;
        uint256 max;
        uint256 total;
        uint256 observations;
    }

    uint256 internal USER_STARTING_BALANCE = 1_000_000_000_000_000;
    uint256 internal BENCHMARK_TRANSFER_AMOUNT = 1_000_000;

    bool constant DEBUG_ACCESSES = false;

    Permit2 permit2;
    TestERC20 token20;
    ContractMock operator;

    uint160 internal alicePk = 0xa11ce;
    uint160 internal bobPk = 0xb0b;
    address payable internal alice = payable(vm.addr(alicePk));
    address payable internal bob = payable(vm.addr(bobPk));

    GasMetrics internal gasMetrics;

    mapping (address => uint256) internal _nonces;

    bytes32 constant MOAR_DATA_HASH = bytes32(0x5a0a5e37edea5678163ef5d7e3aff3ccb4b01f5ad7f84f07b8d55e784223613b);
    bytes32 constant MOAR_DATA_PERMIT_HASH = bytes32(0x4642bb0b01d8bc59f6e90f341ca4ab51207530674e23f9f7df05f2fd07b89e2e);
    string constant MOAR_DATA_TYPE_STRING = "MoarData data)MoarData(uint256 one,uint256 two,uint256 three,uint256 four,uint256 five,uint256 six)";

    function setUp() public virtual {
        setUpMetering({verbose: false});

        permit2 = new Permit2();
        token20 = new TestERC20();
        operator = new ContractMock();

        token20.mint(alice, USER_STARTING_BALANCE);
        token20.mint(bob, USER_STARTING_BALANCE);

        vm.startPrank(alice);
        token20.approve(address(permit2), type(uint256).max);
        uint256 nonce = _getNextNonce(alice);
        (uint256 wordPos, uint256 bitPos) = _bitmapPositions(nonce);
        permit2.invalidateUnorderedNonces(wordPos, bitPos);
        vm.stopPrank();

        vm.startPrank(bob);
        token20.approve(address(permit2), type(uint256).max);
        nonce = _getNextNonce(bob);
        (wordPos, bitPos) = _bitmapPositions(nonce);
        permit2.invalidateUnorderedNonces(wordPos, bitPos);
        vm.stopPrank();

        // Warp to a more realistic timestamp
        vm.warp(1703688340);
    }

    function _clearGasMetrics() internal {
        gasMetrics.min = type(uint256).max;
        gasMetrics.max = 0;
        gasMetrics.total = 0;
        gasMetrics.observations = 0;
    }

    function _updateGasMetrics(uint256 gasMeasurement) internal {
        gasMetrics.min = Math.min(gasMetrics.min, gasMeasurement);
        gasMetrics.max = Math.max(gasMetrics.max, gasMeasurement);
        gasMetrics.total += gasMeasurement;
        gasMetrics.observations++;
    }

    function _logGasMetrics(bool manuallyMetered_, string memory label) internal {
        if (manuallyMetered_) {
            console.log(label);
            console.log("Min: %s", gasMetrics.min);
            console.log("Max: %s", gasMetrics.max);
            console.log("Avg: %s", gasMetrics.total / gasMetrics.observations);
        }
    }

    function _record() internal {
        if (!DEBUG_ACCESSES) {
            return;
        }

        vm.record();
    }

    function _logAccesses(address account) internal {
        if (!DEBUG_ACCESSES) {
            return;
        }

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(account);

        console.log("Reads: %s", reads.length);
        for (uint256 j = 0; j < reads.length; j++) {
            console.logBytes32(reads[j]);
        }
        console.log("Writes: %s", writes.length);
        for (uint256 j = 0; j < writes.length; j++) {
            console.logBytes32(writes[j]);
        }
    }

    function _getNextNonce(address account) internal returns (uint256) {
        uint256 nextUnusedNonce = _nonces[account];
        ++_nonces[account];
        return nextUnusedNonce;
    }

    function _bitmapPositions(uint256 nonce) internal pure returns (uint256 wordPos, uint256 bitPos) {
        wordPos = uint248(nonce >> 8);
        bitPos = uint8(nonce);
    }

    function _getTransferDetails(address to, uint256 amount)
        private
        pure
        returns (ISignatureTransfer.SignatureTransferDetails memory)
    {
        return ISignatureTransfer.SignatureTransferDetails({to: to, requestedAmount: amount});
    }

    function _runBenchmarkCancelNonce(bool manuallyMetered_, uint256 runs, string memory label) internal {
         _clearGasMetrics();

        for (uint256 i = 0; i < runs; i++) {
            uint256 nonce = _getNextNonce(alice);
            (uint256 wordPos, uint256 bitPos) = _bitmapPositions(nonce);

            if (!manuallyMetered_) {
                _record();
                vm.prank(alice);
                permit2.invalidateUnorderedNonces(wordPos, bitPos);
                _logAccesses(address(permit2));
            } else {
                (uint256 gasUsed,) = meterCall({
                    from: alice,
                    to: address(permit2),
                    callData: abi.encodeWithSignature(
                        "invalidateUnorderedNonces(uint256,uint256)", 
                        wordPos,
                        bitPos
                    ),
                    value: 0,
                    transaction: true
                });

                _updateGasMetrics(gasUsed);
            }
        }

        _logGasMetrics(manuallyMetered_, label);
    }

    function _runBenchmarkPermitTransferFromERC20(bool manuallyMetered_, uint256 runs, string memory label) internal {
        _clearGasMetrics();

        for (uint256 i = 0; i < runs; i++) {
            uint256 nonce = _getNextNonce(alice);
            ISignatureTransfer.PermitTransferFrom memory permit = defaultERC20PermitTransfer(address(token20), nonce);
            bytes memory sig = getPermitTransferSignature(permit, alicePk, permit2.DOMAIN_SEPARATOR(), address(operator));
            ISignatureTransfer.SignatureTransferDetails memory transferDetails = _getTransferDetails(bob, BENCHMARK_TRANSFER_AMOUNT);

            if (!manuallyMetered_) {
                _record();
                vm.prank(address(operator), alice);
                permit2.permitTransferFrom(
                    permit, 
                    transferDetails, 
                    alice, 
                    sig);
                _logAccesses(address(permit2));
            } else {
                (uint256 gasUsed,) = meterCall({
                    from: address(operator),
                    to: address(permit2),
                    callData: abi.encodeWithSignature(
                        "permitTransferFrom(((address,uint256),uint256,uint256),(address,uint256),address,bytes)",
                        permit,
                        transferDetails,
                        alice,
                        sig
                    ),
                    value: 0,
                    transaction: true
                });

                _updateGasMetrics(gasUsed);
            }
            
        }

        _logGasMetrics(manuallyMetered_, label);
    }

    function _runBenchmarkPermitTransferFromWithAdditionalDataStringERC20(bool manuallyMetered_, uint256 runs, string memory label) internal {
        _clearGasMetrics();

        for (uint256 i = 0; i < runs; i++) {
            bytes32 witness = keccak256(abi.encode(MOAR_DATA_HASH, 1, 2, 3, 4, 5, 6));
            uint256 nonce = _getNextNonce(alice);
            ISignatureTransfer.PermitTransferFrom memory permit = defaultERC20PermitWitnessTransfer(address(token20), nonce);
            bytes memory sig = getPermitWitnessTransferSignature(permit, alicePk, MOAR_DATA_PERMIT_HASH, witness, permit2.DOMAIN_SEPARATOR(), address(operator));
            ISignatureTransfer.SignatureTransferDetails memory transferDetails = _getTransferDetails(bob, BENCHMARK_TRANSFER_AMOUNT);

            if (!manuallyMetered_) {
                _record();
                vm.prank(address(operator), alice);
                permit2.permitWitnessTransferFrom(
                    permit, 
                    transferDetails, 
                    alice, 
                    witness,
                    MOAR_DATA_TYPE_STRING,
                    sig);
                _logAccesses(address(permit2));
            } else {
                (uint256 gasUsed,) = meterCall({
                    from: address(operator),
                    to: address(permit2),
                    callData: abi.encodeWithSignature(
                        "permitWitnessTransferFrom(((address,uint256),uint256,uint256),(address,uint256),address,bytes32,string,bytes)",
                        permit,
                        transferDetails,
                        alice,
                        witness,
                        MOAR_DATA_TYPE_STRING,
                        sig
                    ),
                    value: 0,
                    transaction: true
                });

                _updateGasMetrics(gasUsed);
            }
            
        }

        _logGasMetrics(manuallyMetered_, label);
    }

    function _runBenchmarkApproveERC20(bool manuallyMetered_, uint256 runs, string memory label) internal {
        _clearGasMetrics();

        for (uint256 i = 0; i < runs; i++) {
            TransferPermit memory permitRequest = TransferPermit({
                token: address(token20),
                id: 0,
                amount: BENCHMARK_TRANSFER_AMOUNT,
                nonce: _getNextNonce(alice),
                operator: address(operator),
                expiration: block.timestamp + 1000,
                signerKey: alicePk,
                owner: alice,
                to: bob
            });

            if (!manuallyMetered_) {
                _record();
                vm.prank(alice);
                permit2.approve(
                    permitRequest.token,
                    permitRequest.operator,
                    uint160(permitRequest.amount),
                    uint48(permitRequest.expiration)
                );
                _logAccesses(address(permit2));
            } else {
                (uint256 gasUsed,) = meterCall({
                    from: alice,
                    to: address(permit2),
                    callData: abi.encodeWithSignature(
                        "approve(address,address,uint160,uint48)", 
                        permitRequest.token,
                        permitRequest.operator,
                        uint160(permitRequest.amount),
                        uint48(permitRequest.expiration)
                    ),
                    value: 0,
                    transaction: true
                });

                _updateGasMetrics(gasUsed);
            }
        }

        _logGasMetrics(manuallyMetered_, label);
    }

    function _runBenchmarkSignatureApproveERC20(bool manuallyMetered_, uint256 runs, string memory label) internal {
        _clearGasMetrics();

        for (uint256 i = 0; i < runs; i++) {
            (,,uint48 nonce) = permit2.allowance(alice, address(token20), address(operator));

            TransferPermit memory permitRequest = TransferPermit({
                token: address(token20),
                id: 0,
                amount: BENCHMARK_TRANSFER_AMOUNT,
                nonce: nonce,
                operator: address(operator),
                expiration: block.timestamp + 1000,
                signerKey: alicePk,
                owner: alice,
                to: bob
            });

            IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
                details: IAllowanceTransfer.PermitDetails({
                    token: permitRequest.token,
                    amount: uint160(permitRequest.amount),
                    expiration: uint48(permitRequest.expiration),
                    nonce: uint48(permitRequest.nonce)
                }),
                spender: permitRequest.operator,
                sigDeadline: permitRequest.expiration
            });

            bytes memory sig = getPermitSignature(permitSingle, alicePk, permit2.DOMAIN_SEPARATOR());

            if (!manuallyMetered_) {
                _record();
                vm.prank(alice);
                permit2.permit(
                    permitRequest.owner,
                    permitSingle,
                    sig
                );
                _logAccesses(address(permit2));
            } else {
                (uint256 gasUsed,) = meterCall({
                    from: alice,
                    to: address(permit2),
                    callData: abi.encodeWithSignature(
                        "permit(address,((address,uint160,uint48,uint48),address,uint256),bytes)", 
                        permitRequest.owner,
                        permitSingle,
                        sig
                    ),
                    value: 0,
                    transaction: true
                });

                _updateGasMetrics(gasUsed);
            }
        }

        _logGasMetrics(manuallyMetered_, label);
    }

    function _runBenchmarkApprovedTransferFromERC20(bool manuallyMetered_, uint256 runs, string memory label) internal {
        _clearGasMetrics();

        for (uint256 i = 0; i < runs; i++) {
            TransferPermit memory permitRequest = TransferPermit({
                token: address(token20),
                id: 0,
                amount: BENCHMARK_TRANSFER_AMOUNT,
                nonce: _getNextNonce(alice),
                operator: address(operator),
                expiration: block.timestamp + 1000,
                signerKey: alicePk,
                owner: alice,
                to: bob
            });
    
            if (!manuallyMetered_) {
                _record();
                vm.prank(address(operator), alice);
                permit2.transferFrom(
                    permitRequest.owner,
                    permitRequest.to,
                    uint160(permitRequest.amount),
                    permitRequest.token
                );
                _logAccesses(address(permit2));
            } else {
                (uint256 gasUsed,) = meterCall({
                    from: address(operator),
                    to: address(permit2),
                    callData: abi.encodeWithSignature(
                        "transferFrom(address,address,uint160,address)", 
                        permitRequest.owner,
                        permitRequest.to,
                        uint160(permitRequest.amount),
                        permitRequest.token
                    ),
                    value: 0,
                    transaction: true
                });

                _updateGasMetrics(gasUsed);
            }
        }

        _logGasMetrics(manuallyMetered_, label);
    }
}
