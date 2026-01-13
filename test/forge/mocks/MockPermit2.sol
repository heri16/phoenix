// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IEIP712} from "permit2/src/interfaces/IEIP712.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

/// @notice Mock Permit2 contract for testing permit2TransferFromWithPermit
contract MockPermit2 is ISignatureTransfer {
    bytes32 public constant _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

    bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 private constant _HASHED_NAME = keccak256("Permit2");

    // Mapping to track used nonces
    mapping(address => mapping(uint256 => uint256)) private _nonceBitmap;

    /// @inheritdoc IEIP712
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, _HASHED_NAME, block.chainid, address(this)));
    }

    /// @inheritdoc ISignatureTransfer
    function nonceBitmap(address owner, uint256 wordPos) external view override returns (uint256) {
        return _nonceBitmap[owner][wordPos];
    }

    /// @inheritdoc ISignatureTransfer
    function permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external override {
        _permitTransferFrom(permit, transferDetails, owner, signature);
    }

    /// @inheritdoc ISignatureTransfer
    function permitWitnessTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32,
        string calldata,
        bytes calldata signature
    ) external override {
        _permitTransferFrom(permit, transferDetails, owner, signature);
    }

    /// @inheritdoc ISignatureTransfer
    function permitTransferFrom(
        PermitBatchTransferFrom memory permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external override {
        // Simplified batch implementation for testing
        require(permit.permitted.length == transferDetails.length, "LengthMismatch()");
        require(block.timestamp <= permit.deadline, SignatureExpired(permit.deadline));

        _useUnorderedNonce(owner, permit.nonce);

        for (uint256 i = 0; i < permit.permitted.length; ++i) {
            require(transferDetails[i].requestedAmount <= permit.permitted[i].amount, "InvalidAmount");
            IERC20(permit.permitted[i].token)
                .transferFrom(owner, transferDetails[i].to, transferDetails[i].requestedAmount);
        }
    }

    /// @inheritdoc ISignatureTransfer
    function permitWitnessTransferFrom(
        PermitBatchTransferFrom memory permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes32,
        string calldata,
        bytes calldata
    ) external override {
        require(permit.permitted.length == transferDetails.length, "LengthMismatch()");
        require(block.timestamp <= permit.deadline, SignatureExpired(permit.deadline));

        _useUnorderedNonce(owner, permit.nonce);

        for (uint256 i = 0; i < permit.permitted.length; ++i) {
            IERC20(permit.permitted[i].token)
                .transferFrom(owner, transferDetails[i].to, transferDetails[i].requestedAmount);
        }
    }

    /// @inheritdoc ISignatureTransfer
    function invalidateUnorderedNonces(uint256 wordPos, uint256 mask) external override {
        _nonceBitmap[msg.sender][wordPos] |= mask;
        emit UnorderedNonceInvalidation(msg.sender, wordPos, mask);
    }

    function _permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) internal {
        // Check deadline
        require(block.timestamp <= permit.deadline, SignatureExpired(permit.deadline));

        // Check amount
        require(transferDetails.requestedAmount <= permit.permitted.amount, InvalidAmount(permit.permitted.amount));

        // Verify signature
        bytes32 tokenPermissions = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        _PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissions, msg.sender, permit.nonce, permit.deadline
                    )
                )
            )
        );

        address signer = _recoverSigner(msgHash, signature);
        require(signer == owner, InvalidSigner());

        // Use nonce
        _useUnorderedNonce(owner, permit.nonce);

        // Transfer tokens
        IERC20(permit.permitted.token).transferFrom(owner, transferDetails.to, transferDetails.requestedAmount);
    }

    function _useUnorderedNonce(address from, uint256 nonce) internal {
        uint256 wordPos = nonce >> 8;
        uint256 bitPos = nonce & 0xff;
        uint256 bit = 1 << bitPos;
        uint256 flipped = _nonceBitmap[from][wordPos] ^= bit;

        require(flipped & bit != 0, InvalidNonce());
    }

    function _recoverSigner(bytes32 hash, bytes calldata signature) internal pure returns (address) {
        require(signature.length == 65, "InvalidSignatureLength");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        return ecrecover(hash, v, r, s);
    }

    error InvalidSigner();
    error InvalidNonce();
    error SignatureExpired(uint256 deadline);
}
