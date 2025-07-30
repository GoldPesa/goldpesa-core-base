// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./NFTUtils.sol";
import {PMCNFTReader} from "./PMCNFTReader.sol";

/**
 * @notice Token URI generator for PumpMarketCap NFTs.
 * @dev This contract constructs a dynamic token URI by:
 *  - Reading SVG data from deployed contracts.
 *  - Injecting dynamic values at pre-defined byte offsets.
 *  - Concatenating the chunks into a complete SVG image.
 *  - Embedding the SVG and metadata (name, ID, address) into a base64-encoded JSON.
 * 
 * Allowing on-chain, customizable, and dynamic metadata generation per token.
 */
contract PMCNFT {
    using NFTUtils for uint256;
    using NFTUtils for address;

    PMCNFTReader public reader;

    constructor(
        PMCNFTReader _reader
    ) {
        reader = _reader;
    }

    /**
     * @dev Constructs the token URI for the NFT.
     * @param nftId The ID of the NFT.
     * @param tokenName The name of the token.
     * @param tokenAddress The address of the token contract.
     * @return string A base64 encoded JSON string representing the NFT metadata.
     */
    function constructTokenURI(
        uint256 nftId,
        string memory tokenName,
        address tokenAddress
    ) external view returns (string memory) {
        string memory nftIdStr = nftId.uintToString(false, 0);
        string memory tokenNameStr = NFTUtils.shortenString(tokenName);
        string memory tokenAddressStr = NFTUtils.shortenString(
            tokenAddress.addressToString()
        );

        // Get SVG data from blob reader
        bytes memory svgBytes = reader.read(
            nftIdStr, 
            tokenNameStr, 
            tokenAddressStr
        );
        string memory svgBase64 = Base64.encode(svgBytes);

        string memory title = string.concat("PumpMarketCap NFT #", nftIdStr);
        string memory description = string.concat(
            "Official PumpMarketCap NFT.\\n",
            "NFT ID: ",
            nftIdStr,
            "\\n",
            "Token Name: ",
            tokenName,
            "\\n",
            "Token Address: ",
            tokenAddress.addressToString(),
            "\\n",
            unicode"⚠️ DISCLAIMER: Verify contract address before transactions."
        );

        return
            string.concat(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"',
                            title,
                            '","description":"',
                            description,
                            '","image":"data:image/svg+xml;base64,',
                            svgBase64,
                            '"}'
                        )
                    )
                )
            );
    }
}
