// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol';
import { StringToAddress, AddressToString } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/utils/AddressString.sol';

import { IAxelarGasService } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol';
// import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';
contract NftLinker is ERC721, IERC721Receiver, AxelarExecutable {
    using StringToAddress for string;
    using AddressToString for address;
    string chainName;
    mapping(uint256 => bytes) public original; //abi.encode(originaChain, operator, tokenId);
    mapping(string => string) public linkers;
    IAxelarGasService public immutable gasService;

    function addLinker(string memory chain, string memory linker) external {
        linkers[chain] = linker;
    }

    constructor(
        string memory chainName_,
        address gateway,
        address gasRecevier
    ) ERC721("Khmer Sl Khmer", "KSK") AxelarExecutable(gateway) {
        chainName = chainName_;
        gasService = IAxelarGasService(gasRecevier);
    }

    function sendNFT(
        address operator,
        uint256 tokenId,
        string memory destinationChain,
        address destinationAddress
    ) external {
        if(operator == address(this)){
            _sendMintedToken(tokenId, destinationChain, destinationAddress);
        } else {
            IERC721(operator).transferFrom(_msgSender(), address(this), tokenId);
            _sendNativeToken(operator, tokenId, destinationChain, destinationAddress);
        }
    }

    function onERC721Received(
        address operator,
        address, /*from*/
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        require(IERC721(operator).ownerOf(tokenId) == address(this), "DID NOT RECEIVE");
        (string memory destinationChain, address destinationAddress) = abi.decode(data, (string, address));
        if(operator == address(this)){
            _sendMintedToken(tokenId, destinationChain, destinationAddress);
        } else {
            _sendNativeToken(operator, tokenId, destinationChain, destinationAddress);
        }
        return this.onERC721Received.selector;
    }

    function sendNFT () external {

    }

        //Burns and sends a token.
    function _sendMintedToken(
        uint256 tokenId,
        string memory destinationChain,
        address destinationAddress
    ) internal {
        _burn(tokenId);
        //Get the original information.
        (string memory originalChain, address operator, uint256 originalTokenId) = abi.decode(
            original[tokenId],
            (string, address, uint256)
        );
        //Create the payload.
        bytes memory payload = abi.encode(originalChain, operator, originalTokenId, destinationAddress);
        string memory stringAddress = address(this).toString();
        //Pay for gas. We could also send the contract call here but then the sourceAddress will be that of the gas receiver which is a problem later.
        gasService.payNativeGasForContractCall{ value: msg.value }(address(this), destinationChain, stringAddress, payload, msg.sender);
        //Call the remote contract.
        gateway.callContract(destinationChain, linkers[destinationChain], payload);
    }

    //Locks and sends a token.
    function _sendNativeToken(
        address operator,
        uint256 tokenId,
        string memory destinationChain,
        address destinationAddress
    ) internal {
        //Create the payload.
        bytes memory payload = abi.encode(chainName, operator, tokenId, destinationAddress);
        string memory stringAddress = address(this).toString();
        //Pay for gas. We could also send the contract call here but then the sourceAddress will be that of the gas receiver which is a problem later.
        gasService.payNativeGasForContractCall{ value: msg.value }(address(this), destinationChain, stringAddress, payload, msg.sender);
        //Call remote contract.
        gateway.callContract(destinationChain, linkers[destinationChain], payload);
    }



    //This is automatically executed by Axelar Microservices since gas was payed for.
    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        //Check that the sender is another token linker.
        require(keccak256(abi.encode(sourceAddress)) == keccak256(abi.encode(linkers[sourceChain])), "NOT_A_LINKER");
        //Decode the payload.
        (
            string memory originalChain,
            address operator,
            uint256 tokenId,
            address destinationAddress
        ) = abi.decode(payload, (string, address, uint256, address));

        if (keccak256(bytes(originalChain)) == keccak256(bytes(chainName))) {
            IERC721(operator).transferFrom(address(this), destinationAddress, tokenId);
            //Otherwise we need to mint a new one.
        } else {
            //We need to save all the relevant information.
            bytes memory originalData = abi.encode(originalChain, operator, tokenId);
            //Avoids tokenId collisions.
            uint256 newTokenId = uint256(keccak256(originalData));
            original[newTokenId] = originalData;
            _safeMint(destinationAddress, newTokenId);
        }
    }
}
