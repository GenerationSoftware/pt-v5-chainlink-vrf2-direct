// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { VRFV2WrapperConsumerBase } from "chainlink/vrf/VRFV2WrapperConsumerBase.sol";
import { Ownable } from "owner-manager/Ownable.sol";

import { VRFV2WrapperInterface } from "chainlink/interfaces/VRFV2WrapperInterface.sol";
import { LinkTokenInterface } from "chainlink/interfaces/LinkTokenInterface.sol";
import { RNGInterface } from "rng-contracts/RNGInterface.sol";

contract ChainlinkVRFV2Direct is VRFV2WrapperConsumerBase, Ownable, RNGInterface {

  /* ============ Global Variables ============ */

  /// @notice A counter for the number of requests made used for request ids
  uint32 internal _requestCounter;

  /// @notice The callback gas limit
  uint32 internal _callbackGasLimit;

  /// @notice The number of blocks to wait before the request starts generating randomness
  uint16 internal _requestConfirmations;

  /// @notice A list of random numbers from past requests mapped by request id
  mapping(uint32 => uint256) internal _randomNumbers;

  /// @notice A list of random number completion timestamps mapped by request id
  mapping(uint32 => uint64) internal requestCompletedAt;

  /// @notice A mapping from Chainlink request ids to internal request ids
  mapping(uint256 => uint32) internal chainlinkRequestIds;

  /* ============ Custom Errors ============ */

  /// @notice Thrown when the LINK token contract address is set to the zero address.
  error LinkTokenZeroAddress();

  /// @notice Thrown when the VRFV2WrapperInterface address is set to the zero address.
  error VRFV2WrapperZeroAddress();

  /// @notice Thrown when the callback gas limit is set to zero.
  error CallbackGasLimitZero();

  /// @notice Thrown when the number of request confirmations is set to zero.
  error RequestConfirmationsZero();

  /// @notice Thrown when the chainlink VRF request ID does not match any stored request IDs.
  error InvalidVrfRequestId(uint256 vrfRequestId);

  /* ============ Custom Events ============ */

  /// @notice Emitted when the callback gas limit is set
  /// @param callbackGasLimit The new callback gas limit
  event SetCallbackGasLimit(uint32 callbackGasLimit);

  /// @notice Emitted when the number of request confirmations is set.
  /// @param requestConfirmations The new request confirmations
  event SetRequestConfirmations(uint16 requestConfirmations);

  /* ============ Constructor ============ */

  /**
   * @notice Constructor of the contract
   * @param _owner Address of the contract owner
   * @param _linkToken Address of the LINK token contract
   * @param _vrfV2Wrapper Address of the VRF V2 Wrapper
   * @param callbackGasLimit_ Gas limit for the fulfillRandomWords callback
   * @param requestConfirmations_ The number of confirmations to wait before fulfilling the request
   */
  constructor(
    address _owner,
    LinkTokenInterface _linkToken,
    VRFV2WrapperInterface _vrfV2Wrapper,
    uint32 callbackGasLimit_,
    uint16 requestConfirmations_
  ) VRFV2WrapperConsumerBase(address(_linkToken), address(_vrfV2Wrapper)) Ownable(_owner) {
    if (address(_linkToken) == address(0)) revert LinkTokenZeroAddress();
    if (address(_vrfV2Wrapper) == address(0)) revert VRFV2WrapperZeroAddress();
    _setCallbackGasLimit(callbackGasLimit_);
    _setRequestConfirmations(requestConfirmations_);
  }

  /* ============ External Functions ============ */

  /// @inheritdoc RNGInterface
  function requestRandomNumber()
    external
    returns (uint32 requestId, uint32 lockBlock)
  {
    uint256 _vrfRequestId = requestRandomness(
      _callbackGasLimit, // TODO: make callback gas updateable or configurable by caller
      _requestConfirmations,
      1 // num words
    );

    _requestCounter = _requestCounter + 1;

    requestId = _requestCounter;
    chainlinkRequestIds[_vrfRequestId] = _requestCounter;

    lockBlock = uint32(block.number + _requestConfirmations);

    emit RandomNumberRequested(_requestCounter, msg.sender);
  }

  /// @inheritdoc RNGInterface
  function isRequestComplete(uint32 _internalRequestId)
    external
    view
    override
    returns (bool isCompleted)
  {
    return _randomNumbers[_internalRequestId] != 0;
  }

  /// @inheritdoc RNGInterface
  function randomNumber(uint32 _internalRequestId)
    external
    view
    override
    returns (uint256 randomNum)
  {
    return _randomNumbers[_internalRequestId];
  }

  /**
   * @inheritdoc RNGInterface
   * @dev Returns zero if not completed or if the request doesn't exist
   */
  function completedAt(uint32 requestId) external view override returns (uint64 completedAtTimestamp) {
    return requestCompletedAt[requestId];
  }

  /// @inheritdoc RNGInterface
  function getLastRequestId() external view override returns (uint32 requestId) {
    return _requestCounter;
  }

  /// @inheritdoc RNGInterface
  function getRequestFee() external view override returns (address feeToken, uint256 requestFee) {
    return (address(LINK), VRF_V2_WRAPPER.calculateRequestPrice(_callbackGasLimit));
  }

  /* ============ External Setters ============ */

  function setCallbackGasLimit(uint32 callbackGasLimit_) external onlyOwner {
    _setCallbackGasLimit(callbackGasLimit_);
  }

  function setRequestConfirmations(uint16 requestConfirmations_) external onlyOwner {
    _setRequestConfirmations(requestConfirmations_);
  }

  /* ============ Internal Functions ============ */

  /**
   * @notice Callback function called by VRF Wrapper
   * @dev The VRF Wrapper will only call it once it has verified the proof associated with the randomness.
   * @param _vrfRequestId Chainlink VRF request id
   * @param _randomWords Chainlink VRF array of random words
   */
  function fulfillRandomWords(uint256 _vrfRequestId, uint256[] memory _randomWords)
    internal
    override
  {
    uint32 _internalRequestId = chainlinkRequestIds[_vrfRequestId];
    if (_internalRequestId == 0) revert InvalidVrfRequestId(_vrfRequestId);

    uint256 _randomNumber = _randomWords[0];
    _randomNumbers[_internalRequestId] = _randomNumber;
    requestCompletedAt[_internalRequestId] = uint64(block.timestamp);

    emit RandomNumberCompleted(_internalRequestId, _randomNumber);
  }

  /* ============ Internal Setters ============ */

  function _setCallbackGasLimit(uint32 callbackGasLimit_) internal {
    if (callbackGasLimit_ == 0) revert CallbackGasLimitZero();
    _callbackGasLimit = callbackGasLimit_;
    emit SetCallbackGasLimit(_callbackGasLimit);
  }

  function _setRequestConfirmations(uint16 requestConfirmations_) internal {
    if (requestConfirmations_ == 0) revert RequestConfirmationsZero();
    _requestConfirmations = requestConfirmations_;
    emit SetRequestConfirmations(_requestConfirmations);
  }

}
