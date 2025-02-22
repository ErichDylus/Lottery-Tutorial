// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Lottery is RrpRequesterV0, Ownable {
    // Events
    event RequestedRandomNumber(bytes32 indexed requestId);
    event ReceivedRandomNumber(bytes32 indexed requestId, uint256 randomNumber);

    // Global Variables
    uint256 public pot = 0; // total amount of ether in the pot
    uint256 public ticketPrice = 0.0001 ether; // price of a single ticket
    uint256 public week = 1; // current week counter
    uint256 public endTime; // datetime that current week ends and lottery is closable
    uint256 public constant MAX_NUMBER = 10000; // highest possible number
    address public constant airnodeAddress =
        0x9d3C147cA16DB954873A498e0af5852AB39139f2;
    bytes32 public constant endpointId =
        0xfb6d017bb87991b7495f563db3c8cf59ff87b09781947bb1e417006ad7f55a78;
    address public sponsorWallet;

    // Mappings
    mapping(uint256 => mapping(uint256 => address[])) public tickets; // mapping of week => entry number choice => list of addresses that bought that entry number
    mapping(uint256 => uint256) public winningNumber; // mapping to store each weeks winning number
    mapping(bytes32 => bool) public pendingRequestIds; // mapping to store pending request ids

    /// @notice Initialize the contract with a set day and time of the week winners can be chosen
    /// @param _endTime date and time when the lottery becomes closable
    constructor(uint256 _endTime, address _airnodeRrpAddress)
        RrpRequesterV0(_airnodeRrpAddress)
    {
        require(_endTime > block.timestamp, "End time must be in the future");
        endTime = _endTime; // store the end time of the lottery
    }

    function setSponsorWallet(address _sponsorWallet) public onlyOwner {
        sponsorWallet = _sponsorWallet;
    }

    /// @notice Buy a ticket for the current week
    /// @param _number The number to buy a ticket for
    function enter(uint256 _number) public payable {
        require(_number <= MAX_NUMBER, "Number must be 1-MAX_NUMBER"); // guess has to be between 1 and MAX_NUMBER
        require(block.timestamp < endTime, "Lottery has ended"); // lottery has to be open
        require(msg.value == ticketPrice, "Ticket price is 0.0001 ether"); // user needs to send 0.0001 ether with the transaction
        tickets[week][_number].push(msg.sender); // add user's address to list of entries for their number under the current week
        pot += ticketPrice; // account for the ticket sale in the pot
    }

    /// @notice Request winning random number from Airnode
    function getWinningNumber() public payable {
        // require(block.timestamp > endTime, "Lottery has not ended"); // not available until end time has passed
        require(msg.value >= 0.01 ether, "Please top up sponsor wallet"); // user needs to send 0.01 ether with the transaction
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnodeAddress,
            endpointId,
            address(this),
            sponsorWallet,
            address(this),
            this.closeWeek.selector,
            ""
        );
        pendingRequestIds[requestId] = true;
        emit RequestedRandomNumber(requestId);
        payable(sponsorWallet).transfer(msg.value); // Send funds to sponsor wallet
    }

    /// @notice Close the current week and calculate the winners. Can be called by anyone after the end time has passed.
    /// @param requestId the request id of the response from Airnode
    /// @param data payload returned by Airnode
    function closeWeek(bytes32 requestId, bytes calldata data)
        public
        onlyAirnodeRrp
    {
        require(pendingRequestIds[requestId], "No such request made");
        delete pendingRequestIds[requestId]; // remove request id from pending request ids

        uint256 _randomNumber = abi.decode(data, (uint256)) % MAX_NUMBER; // get the random number from the data
        emit ReceivedRandomNumber(requestId, _randomNumber); // emit the random number as an event

        // require(block.timestamp > endTime, "Lottery is open"); // will prevent duplicate closings. If someone closed it first it will increment the end time and not allow

        winningNumber[week] = _randomNumber;
        address[] memory winners = tickets[week][_randomNumber]; // get list of addresses that chose the random number this week
        week++; // increment week counter
        endTime += 7 days; // set end time for 7 days later
        if (winners.length > 0) {
            uint256 earnings = pot / winners.length; // divide pot evenly among winners
            pot = 0; // reset pot
            for (uint256 i = 0; i < winners.length; i++) {
                payable(winners[i]).transfer(earnings); // send earnings to each winner
            }
        }
    }

    /// @notice Read only function to get addresses entered into a specific number for a specific week
    /// @param _week The week to get the list of addresses for
    /// @param _number The number to get the list of addresses for
    function getEntriesForNumber(uint256 _number, uint256 _week)
        public
        view
        returns (address[] memory)
    {
        return tickets[_week][_number];
    }
}
