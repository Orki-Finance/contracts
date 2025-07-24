// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
//import "forge-std/StdAssertions.sol";
import "src/NFTMetadata/MetadataNFT.sol";
import "src/NFTMetadata/utils/Utils.sol";
import "src/NFTMetadata/utils/FixedAssets.sol";

contract MetadataDeployment is Script /* , StdAssertions */ {
    struct File {
        bytes data;
        uint256 start;
        uint256 end;
    }

    mapping(bytes4 => File) public files;

    address public pointer;

    FixedAssetReader public initializedFixedAssetReader;

    function deployMetadata(bytes32 _salt) public returns (MetadataNFT) {
        _loadFiles();
        _storeFile();
        _deployFixedAssetReader(_salt);

        MetadataNFT metadataNFT = new MetadataNFT{salt: _salt}(initializedFixedAssetReader);

        return metadataNFT;
    }

    function _loadFiles() internal {
        string memory root = string.concat(vm.projectRoot(), "/utils/assets/");

        //emit log_string(root);

        uint256 offset = 0;

        //read bold file

        bytes memory quillFile = bytes(vm.readFile(string.concat(root, "quill_logo.txt")));
        File memory quill = File(quillFile, offset, offset + quillFile.length);

        offset += quillFile.length;

        files[bytes4(keccak256("USDQ"))] = quill;

        //read eth file
        bytes memory ethFile = bytes(vm.readFile(string.concat(root, "weth_logo.txt")));
        File memory eth = File(ethFile, offset, offset + ethFile.length);

        offset += ethFile.length;

        files[bytes4(keccak256("WETH"))] = eth;

        //read wstETH file
        bytes memory wstethFile = bytes(vm.readFile(string.concat(root, "wsteth_logo.txt")));
        File memory wsteth = File(wstethFile, offset, offset + wstethFile.length);

        offset += wstethFile.length;

        files[bytes4(keccak256("wstETH"))] = wsteth;

        // //read rETH file
        // bytes memory rethFile = bytes(vm.readFile(string.concat(root, "reth_logo.txt")));
        // File memory reth = File(rethFile, offset, offset + rethFile.length);

        // offset += rethFile.length;

        // files[bytes4(keccak256("rETH"))] = reth;

        //read geist font file
        bytes memory geistFile = bytes(vm.readFile(string.concat(root, "geist.txt")));
        File memory geist = File(geistFile, offset, offset + geistFile.length);

        offset += geistFile.length;

        files[bytes4(keccak256("geist"))] = geist;

        //read weeth file
        bytes memory weethFile = bytes(vm.readFile(string.concat(root, "weeth_logo.txt")));
        File memory weeth = File(weethFile, offset, offset + weethFile.length);

        offset += weethFile.length;

        files[bytes4(keccak256("weETH"))] = weeth;

        //read scr file
        bytes memory scrFile = bytes(vm.readFile(string.concat(root, "scroll_logo.txt")));
        File memory scr = File(scrFile, offset, offset + scrFile.length);

        offset += scrFile.length;

        files[bytes4(keccak256("SCR"))] = scr;
    }

    function _storeFile() internal {
        bytes memory data = bytes.concat(
            files[bytes4(keccak256("USDQ"))].data,
            files[bytes4(keccak256("WETH"))].data,
            files[bytes4(keccak256("wstETH"))].data,
            // files[bytes4(keccak256("rETH"))].data,
            files[bytes4(keccak256("geist"))].data,
            files[bytes4(keccak256("weETH"))].data,
            files[bytes4(keccak256("SCR"))].data
        );

        //emit log_named_uint("data length", data.length);

        pointer = SSTORE2.write(data);
    }

    function _deployFixedAssetReader(bytes32 _salt) internal {
        bytes4[] memory sigs = new bytes4[](6);
        sigs[0] = bytes4(keccak256("USDQ"));
        sigs[1] = bytes4(keccak256("WETH"));
        sigs[2] = bytes4(keccak256("wstETH"));
        // sigs[3] = bytes4(keccak256("rETH"));
        sigs[3] = bytes4(keccak256("geist"));
        sigs[4] = bytes4(keccak256("weETH"));
        sigs[5] = bytes4(keccak256("SCR"));

        FixedAssetReader.Asset[] memory FixedAssets = new FixedAssetReader.Asset[](6);
        FixedAssets[0] = FixedAssetReader.Asset(
            uint128(files[bytes4(keccak256("USDQ"))].start), uint128(files[bytes4(keccak256("USDQ"))].end)
        );
        FixedAssets[1] = FixedAssetReader.Asset(
            uint128(files[bytes4(keccak256("WETH"))].start), uint128(files[bytes4(keccak256("WETH"))].end)
        );
        FixedAssets[2] = FixedAssetReader.Asset(
            uint128(files[bytes4(keccak256("wstETH"))].start), uint128(files[bytes4(keccak256("wstETH"))].end)
        );
        // FixedAssets[3] = FixedAssetReader.Asset(
        //     uint128(files[bytes4(keccak256("rETH"))].start), uint128(files[bytes4(keccak256("rETH"))].end)
        // );
        FixedAssets[3] = FixedAssetReader.Asset(
            uint128(files[bytes4(keccak256("geist"))].start), uint128(files[bytes4(keccak256("geist"))].end)
        );
        FixedAssets[4] = FixedAssetReader.Asset(
            uint128(files[bytes4(keccak256("weETH"))].start), uint128(files[bytes4(keccak256("weETH"))].end)
        );
        FixedAssets[5] = FixedAssetReader.Asset(
            uint128(files[bytes4(keccak256("SCR"))].start), uint128(files[bytes4(keccak256("SCR"))].end)
        );

        initializedFixedAssetReader = new FixedAssetReader{salt: _salt}(pointer, sigs, FixedAssets);
    }
}
