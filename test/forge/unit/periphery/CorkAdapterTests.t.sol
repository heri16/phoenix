// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Call} from "bundler3/interfaces/IBundler3.sol";
import {ErrorsLib} from "bundler3/libraries/ErrorsLib.sol";
import {ICorkAdapter} from "contracts/interfaces/ICorkAdapter.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {CorkAdapter} from "contracts/periphery/CorkAdapter.sol";
import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {SigUtils} from "test/forge/helpers/SigUtils.sol";
import {DummyWETH, ERC20Mock} from "test/forge/mocks/DummyWETH.sol";
import {MockBundler3} from "test/forge/mocks/MockBundler3.sol";
import {MockPermit2} from "test/forge/mocks/MockPermit2.sol";

contract CorkAdapterTests is Test, SigUtils {
    address ensOwner = makeAddr("ensOwner");
    address defaultAdmin = makeAddr("defaultAdmin");
    address alice;
    uint256 alicePk;

    address eve = makeAddr("eve");
    address bundler3 = makeAddr("bundler3");
    address cork = makeAddr("cork");
    address whitelistManager = makeAddr("whitelistManager");
    address receiver = makeAddr("receiver");

    CorkAdapter corkAdapter;
    MockBundler3 mockBundler;
    ERC20Mock testToken;
    MockPermit2 permit2;

    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint256 constant DEFAULT_NONCE = 0;
    uint256 constant DEFAULT_TRANSFER_AMOUNT = 1 ether;

    function setUp() public {
        // Create alice with a known private key for signing
        (alice, alicePk) = makeAddrAndKey("alice");

        // Deploy MockPermit2 and etch it to canonical address
        MockPermit2 permit2Impl = new MockPermit2();
        vm.etch(PERMIT2_ADDRESS, address(permit2Impl).code);
        permit2 = MockPermit2(PERMIT2_ADDRESS);

        // Deploy MockBundler3 and etch it to bundler3 address
        MockBundler3 bundlerImpl = new MockBundler3();
        vm.etch(bundler3, address(bundlerImpl).code);
        mockBundler = MockBundler3(bundler3);

        // Deploy test token
        testToken = new DummyWETH();

        vm.startPrank(defaultAdmin);
        corkAdapter = new CorkAdapter(defaultAdmin);
        corkAdapter.initialize(ensOwner, bundler3, cork, whitelistManager);
        vm.stopPrank();

        // Give alice some tokens and approve Permit2
        vm.deal(alice, 100 ether);
        vm.startPrank(alice);
        testToken.deposit{value: 10 ether}();
        testToken.approve(PERMIT2_ADDRESS, type(uint256).max);
        vm.stopPrank();
    }

    //------------------------------------------ Tests for corkAdapter constructor -------------------------------------//
    function test_corkAdapterConstructor_shouldRevert_whenPassedZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new CorkAdapter(address(0));
    }

    function test_corkAdapterInitialize_shouldRevert_whenPassedZeroAddress() public {
        vm.startPrank(defaultAdmin);
        corkAdapter = new CorkAdapter(defaultAdmin);

        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.initialize(address(0), bundler3, cork, whitelistManager);

        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.initialize(ensOwner, address(0), cork, whitelistManager);

        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.initialize(ensOwner, bundler3, address(0), whitelistManager);

        vm.expectRevert(IErrors.ZeroAddress.selector);
        corkAdapter.initialize(ensOwner, bundler3, cork, address(0));
        vm.stopPrank();
    }

    function test_corkAdapterInitialize_shouldRevert_whenInitializingTwice() public {
        vm.startPrank(ensOwner);
        vm.expectRevert(ICorkAdapter.InvalidInitialization.selector);
        corkAdapter.initialize(ensOwner, bundler3, cork, whitelistManager);
    }

    function test_corkAdapterInitialize_shouldRevert_whenInitializedByNonOwner() public {
        vm.startPrank(eve);
        corkAdapter = new CorkAdapter(defaultAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, eve));
        corkAdapter.initialize(ensOwner, bundler3, cork, whitelistManager);
    }

    function test_corkAdapterConstructor_shouldWorkCorrectly() public {
        assertEq(address(corkAdapter.CORK()), cork);
        assertEq(address(corkAdapter.WHITELIST_MANAGER()), whitelistManager);
        assertEq(address(corkAdapter.BUNDLER3()), bundler3);
        assertEq(address(corkAdapter.owner()), ensOwner);
    }

    //------------------------------------------ Tests for permit2TransferFromWithPermit -------------------------------------//

    function test_permit2TransferFromWithPermit_shouldWorkCorrectly() public {
        (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory signature) =
            _createSignedPermit(DEFAULT_TRANSFER_AMOUNT, DEFAULT_NONCE, _defaultDeadline(), alicePk);
        Call[] memory calls = _buildPermit2Call(permit, signature, receiver, DEFAULT_TRANSFER_AMOUNT);

        uint256 aliceBalanceBefore = testToken.balanceOf(alice);
        uint256 receiverBalanceBefore = testToken.balanceOf(receiver);

        vm.prank(alice);
        mockBundler.multicall(calls);

        assertEq(testToken.balanceOf(alice), aliceBalanceBefore - DEFAULT_TRANSFER_AMOUNT);
        assertEq(testToken.balanceOf(receiver), receiverBalanceBefore + DEFAULT_TRANSFER_AMOUNT);
    }

    function test_permit2TransferFromWithPermit_shouldWorkCorrectly_withMaxAmount() public {
        uint256 aliceBalance = testToken.balanceOf(alice);
        (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory signature) =
            _createSignedPermit(aliceBalance, DEFAULT_NONCE, _defaultDeadline(), alicePk);
        Call[] memory calls = _buildPermit2Call(permit, signature, receiver, type(uint256).max);

        uint256 receiverBalanceBefore = testToken.balanceOf(receiver);

        vm.prank(alice);
        mockBundler.multicall(calls);

        assertEq(testToken.balanceOf(alice), 0);
        assertEq(testToken.balanceOf(receiver), receiverBalanceBefore + aliceBalance);
    }

    function test_permit2TransferFromWithPermit_shouldRevert_whenReceiverIsZeroAddress() public {
        (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory signature) =
            _createSignedPermit(DEFAULT_TRANSFER_AMOUNT, DEFAULT_NONCE, _defaultDeadline(), alicePk);
        Call[] memory calls = _buildPermit2Call(permit, signature, address(0), DEFAULT_TRANSFER_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        mockBundler.multicall(calls);
    }

    function test_permit2TransferFromWithPermit_shouldRevert_whenAmountIsZero() public {
        (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory signature) =
            _createSignedPermit(DEFAULT_TRANSFER_AMOUNT, DEFAULT_NONCE, _defaultDeadline(), alicePk);
        Call[] memory calls = _buildPermit2Call(permit, signature, receiver, 0);

        vm.prank(alice);
        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        mockBundler.multicall(calls);
    }

    function test_permit2TransferFromWithPermit_shouldRevert_whenCalledDirectly() public {
        (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory signature) =
            _createSignedPermit(DEFAULT_TRANSFER_AMOUNT, DEFAULT_NONCE, _defaultDeadline(), alicePk);

        vm.prank(alice);
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        corkAdapter.permit2TransferFromWithPermit(permit, signature, receiver, DEFAULT_TRANSFER_AMOUNT);
    }

    function test_permit2TransferFromWithPermit_shouldRevert_whenDeadlineExpired() public {
        uint256 expiredDeadline = block.timestamp - 1;
        (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory signature) =
            _createSignedPermit(DEFAULT_TRANSFER_AMOUNT, DEFAULT_NONCE, expiredDeadline, alicePk);
        Call[] memory calls = _buildPermit2Call(permit, signature, receiver, DEFAULT_TRANSFER_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("SignatureExpired(uint256)", expiredDeadline));
        mockBundler.multicall(calls);
    }

    function test_permit2TransferFromWithPermit_shouldRevert_whenInvalidSignature() public {
        (, uint256 evePk) = makeAddrAndKey("eve_signer");
        ISignatureTransfer.PermitTransferFrom memory permit =
            _createPermit(DEFAULT_TRANSFER_AMOUNT, DEFAULT_NONCE, _defaultDeadline());
        bytes memory invalidSignature = _signPermit(DEFAULT_TRANSFER_AMOUNT, DEFAULT_NONCE, _defaultDeadline(), evePk);
        Call[] memory calls = _buildPermit2Call(permit, invalidSignature, receiver, DEFAULT_TRANSFER_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        mockBundler.multicall(calls);
    }

    //------------------------------------------ Permit2 Helper Functions -------------------------------------//

    function _defaultDeadline() internal view returns (uint256) {
        return block.timestamp + 1 hours;
    }

    function _createPermit(uint256 amount, uint256 nonce, uint256 deadline)
        internal
        view
        returns (ISignatureTransfer.PermitTransferFrom memory)
    {
        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(testToken), amount: amount}),
            nonce: nonce,
            deadline: deadline
        });
    }

    function _signPermit(uint256 amount, uint256 nonce, uint256 deadline, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        return getPermitTransferFromSignature(
            address(testToken), amount, nonce, deadline, address(corkAdapter), pk, permit2.DOMAIN_SEPARATOR()
        );
    }

    function _createSignedPermit(uint256 amount, uint256 nonce, uint256 deadline, uint256 pk)
        internal
        view
        returns (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory signature)
    {
        permit = _createPermit(amount, nonce, deadline);
        signature = _signPermit(amount, nonce, deadline, pk);
    }

    function _buildPermit2Call(
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory signature,
        address _receiver,
        uint256 amount
    ) internal view returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = Call({
            to: address(corkAdapter),
            data: abi.encodeCall(corkAdapter.permit2TransferFromWithPermit, (permit, signature, _receiver, amount)),
            value: 0,
            skipRevert: false,
            callbackHash: bytes32(0)
        });
    }
}
