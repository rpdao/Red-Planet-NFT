// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract RED_PLANET is ERC721, ERC2981, Ownable {

    // ===== ERRORS =====

    error SoldOut();
    error WrongPhase();
    error InvalidAmount();
    error InvalidID();
    error AlreadyMinted();
    error BadETHValue();
    error TransferFailed();

    // ===== CONFIG =====

    uint256 public constant MAX_SUPPLY = 5000;
    uint256 public constant MAX_PER_TX = 10;

    uint256 public priceUSDC = 30 * 1e6;
    uint256 public priceETH  = 14285000000000000;

    IERC20 public immutable USDC;

    address public teamWallet;

    string private baseURI;

    enum Phase { Airdrop, Public, Paused, Finished }
    Phase public phase = Phase.Paused;

    // ===== RANDOM SUPPLY LOGIC =====

    uint256 public remaining = MAX_SUPPLY;
    mapping(uint256 => uint256) private availableIds;

    // ===== CONSTRUCTOR =====

    constructor(
        address _usdc,
        address _teamWallet,
        string memory baseURI_
    )
        ERC721("RED PLANET", "RP")
        Ownable(msg.sender)
    {
        USDC = IERC20(_usdc);
        teamWallet = _teamWallet;
        baseURI = baseURI_;

        _setDefaultRoyalty(_teamWallet, 500);
    }

    // ===== INTERNAL =====

    function _getRandomId(address minter) internal returns (uint256 id) {
        if (remaining == 0) revert SoldOut();

        uint256 rand = uint256(
            keccak256(
                abi.encodePacked(
                    minter,
                    block.prevrandao,
                    block.timestamp,
                    remaining
                )
            )
        );

        uint256 index = rand % remaining;

        id = availableIds[index];
        if (id == 0) id = index + 1;

        uint256 last = availableIds[remaining - 1];
        if (last == 0) last = remaining;

        availableIds[index] = last;
        remaining--;
    }

    function _burnFromRandom(uint256 id) internal {
        uint256 lastIndex = remaining - 1;

        for (uint256 i; i < remaining; ) {
            uint256 cur = availableIds[i];
            if (cur == 0) cur = i + 1;

            if (cur == id) {
                uint256 last = availableIds[lastIndex];
                if (last == 0) last = lastIndex + 1;

                availableIds[i] = last;
                remaining--;
                return;
            }

            unchecked { ++i; }
        }

        revert InvalidID();
    }

    // ===== AIRDROP =====

    function airdrop(address to, uint256[] calldata ids)
        external
        onlyOwner
    {
        if (phase != Phase.Airdrop) revert WrongPhase();

        uint256 len = ids.length;
        for (uint256 i; i < len; ) {
            uint256 id = ids[i];

            if (id == 0 || id > MAX_SUPPLY) revert InvalidID();
            if (_ownerOf(id) != address(0)) revert AlreadyMinted();

            _burnFromRandom(id);
            _safeMint(to, id);

            unchecked { ++i; }
        }
    }

    // ===== PUBLIC MINT =====

    function mintUSDC(uint256 amount) external {
        if (phase != Phase.Public) revert WrongPhase();
        if (amount == 0 || amount > MAX_PER_TX) revert InvalidAmount();

        uint256 cost = priceUSDC * amount;
        if (!USDC.transferFrom(msg.sender, teamWallet, cost)) {
            revert TransferFailed();
        }

        for (uint256 i; i < amount; ) {
            uint256 id = _getRandomId(msg.sender);
            _safeMint(msg.sender, id);
            unchecked { ++i; }
        }
    }

    function mintETH(uint256 amount) external payable {
        if (phase != Phase.Public) revert WrongPhase();
        if (amount == 0 || amount > MAX_PER_TX) revert InvalidAmount();
        if (msg.value != priceETH * amount) revert BadETHValue();

        (bool ok, ) = teamWallet.call{value: msg.value}("");
        if (!ok) revert TransferFailed();

        for (uint256 i; i < amount; ) {
            uint256 id = _getRandomId(msg.sender);
            _safeMint(msg.sender, id);
            unchecked { ++i; }
        }
    }

    // ===== ADMIN =====

    function setPhase(Phase phase_) external onlyOwner {
        if (phase == Phase.Finished) revert WrongPhase();
        phase = phase_;
    }

    function setPriceUSDC(uint256 usdc) external onlyOwner {
        priceUSDC = usdc;
    }

    function setPriceETH(uint256 eth) external onlyOwner {
        priceETH = eth;
    }

    function setBaseURI(string calldata url) external onlyOwner {
        baseURI = url;
    }

    function setTeamWallet(address new_address) external onlyOwner {
        teamWallet = new_address;
        _setDefaultRoyalty(new_address, 500);
    }

    function setRoyalty(address receiver, uint96 feeNumerator)
        external
        onlyOwner
    {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    // ===== METADATA =====

    function _baseURI()
        internal
        view
        override
        returns (string memory)
    {
        return baseURI;
    }

    function tokenURI(uint256 id)
        public
        view
        override
        returns (string memory)
    {
        if (_ownerOf(id) == address(0)) revert InvalidID();

        return string(
            abi.encodePacked(
                baseURI,
                Strings.toString(id),
                ".json"
            )
        );
    }

    // ===== ROYALTY =====

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

