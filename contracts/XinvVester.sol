/// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.5.16;

import "./SafeMath.sol";

interface Ixinv {
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function syncDelegate(address user) external;
}

interface Iinv {
    function balanceOf(address account) external view returns (uint);
    function transfer(address dst, uint rawAmount) external returns (bool);
    function delegate(address delegatee) external;
    function approve(address spender, uint rawAmount) external returns (bool);
    function transferFrom(address src, address dst, uint rawAmount) external returns (bool);
}

contract XinvVesterFactory {

    address public governance;
    Iinv public inv;
    Ixinv public xinv;
    XinvVester[] public vesters;

    constructor (Ixinv _xinv, Iinv _inv, address _governance) public {
        governance = _governance;
        inv = _inv;
        xinv = _xinv;
    }

    function deployVester(address _recipient, uint _invAmount, uint _vestingDurationSeconds, bool _isCancellable) public {
        require(msg.sender == governance, "ONLY GOVERNANCE");
        XinvVester vester = new XinvVester(xinv, inv, governance, _recipient, _vestingDurationSeconds, _isCancellable);
        inv.transferFrom(governance, address(vester), _invAmount);
        vester.initialize();
        vesters.push(vester);
    }
}

// Should only be deployed via factory
// Assumes xINV withdrawal delay is permanently set to 0
contract XinvVester {
    using SafeMath for uint;

    address public governance;
    address public factory;
    address public recipient;
    Iinv public inv;
    Ixinv public xinv;

    uint public vestingXinvAmount;
    uint public vestingBegin;
    uint public vestingEnd;
    bool public isCancellable;
    bool public isCancelled;
    uint public lastUpdate;

    constructor(Ixinv _xinv, Iinv _inv, address _governance, address _recipient, uint _vestingDurationSeconds, bool _isCancellable) public {
        require(_vestingDurationSeconds > 0, "DURATION IS 0");
        inv = _inv;
        xinv = _xinv;
        vestingBegin = block.timestamp;
        vestingEnd = vestingBegin + _vestingDurationSeconds;
        recipient = _recipient;
        isCancellable = _isCancellable;
        governance = _governance;
        factory = msg.sender;

        lastUpdate = block.timestamp;

        inv.delegate(_recipient);
        xinv.syncDelegate(address(this));
    }

    function initialize() public {
        uint _invAmount = inv.balanceOf(address(this));
        require(_invAmount > 0, "INV AMOUNT IS 0");
        require(msg.sender == factory, "ONLY FACTORY");
        inv.approve(address(xinv), _invAmount);
        require(xinv.mint(_invAmount) == 0, "MINT FAILED");
        vestingXinvAmount = xinv.balanceOf(address(this));
    }

    function delegate(address delegate_) public {
        require(msg.sender == recipient, 'ONLY RECIPIENT');
        inv.delegate(delegate_);
        xinv.syncDelegate(address(this));
    }

    function setRecipient(address recipient_) public {
        require(msg.sender == recipient, 'ONLY RECIPIENT');
        recipient = recipient_;
    }

    function claimableXINV() public view returns (uint xinvAmount) {
        if (isCancelled) return 0;
        if (block.timestamp >= vestingEnd) {
            xinvAmount = xinv.balanceOf(address(this));
        } else {
            xinvAmount = vestingXinvAmount.mul(block.timestamp - lastUpdate).div(vestingEnd - vestingBegin);
        }
    }

    function claim() public {
        require(xinv.redeem(claimableXINV()) == 0, "REDEEM FAILED");
        inv.transfer(recipient, inv.balanceOf(address(this)));
    }

    function cancel() public {
        require(msg.sender == governance, "ONLY GOVERNANCE");
        require(isCancellable, "NOT CANCELLABLE");
        require(!isCancelled, "ALREADY CANCELLED");
        claim();
        require(xinv.redeem(xinv.balanceOf(address(this))) == 0, "REDEEM FAILED");
        inv.transfer(governance, inv.balanceOf(address(this)));
        isCancelled = true;
    }

}