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

    mapping(string => string) private collateralToFile;

    function deployMetadata(bytes32 _salt, string memory _coll) public returns (MetadataNFT) {
        collateralToFile["WETH"] = "weth_logo.txt";
        collateralToFile["weETH"] = "weeth_logo.txt";
        collateralToFile["rswETH"] = "rsweth_logo.txt";
        collateralToFile["ezETH"] = "ezeth_logo.txt";
        collateralToFile["rsETH"] = "rseth_logo.txt";
        collateralToFile["swETH"] = "sweth_logo.txt";
        collateralToFile["swBTC"] = "swbtc_logo.txt";
        collateralToFile["SWELL"] = "swell_logo.txt";
        collateralToFile["SCR"] = "scroll_logo.txt";
        collateralToFile["wstETH"] = "wsteth_logo.txt";
        collateralToFile["rETH"] = "reth_logo.txt";
        collateralToFile["LST"] = "reth_logo.txt";
        collateralToFile["NC"] = "reth_logo.txt";

        _loadMainFiles(_coll);
        _storeFile(_coll);
        _deployFixedAssetReader(_salt, _coll);

        MetadataNFT metadataNFT = new MetadataNFT{salt: _salt}(initializedFixedAssetReader);

        return metadataNFT;
    }

    function _loadMainFiles(string memory coll) internal {
        string memory root = string.concat(vm.projectRoot(), "/utils/assets/");

        //emit log_string(root);

        uint256 offset = 0;

        //read bold file

        bytes memory usdkFile = bytes(vm.readFile(string.concat(root, "usdk_logo.txt")));
        File memory usdk = File(usdkFile, offset, offset + usdkFile.length);

        offset += usdkFile.length;

        files[bytes4(keccak256("USDK"))] = usdk;

        bytes memory orkiFile = bytes(vm.readFile(string.concat(root, "orkionblack.txt")));
        File memory orki = File(orkiFile, offset, offset + orkiFile.length);

        offset += orkiFile.length;

        files[bytes4(keccak256("ORKI"))] = orki;

        //read geist font file
        bytes memory geistFile = bytes(vm.readFile(string.concat(root, "geist.txt")));
        File memory geist = File(geistFile, offset, offset + geistFile.length);

        offset += geistFile.length;

        files[bytes4(keccak256("geist"))] = geist;

        string memory filename = collateralToFile[coll];
        require(bytes(filename).length > 0, string.concat("Invalid collateral symbol", coll));

        bytes memory collFile = bytes(vm.readFile(string.concat(root, filename)));
        File memory collData = File(collFile, offset, offset + collFile.length);
        offset += collFile.length;
        files[bytes4(keccak256(abi.encodePacked(coll)))] = collData;
    }

    function _storeFile(string memory coll) internal {
        bytes memory data = bytes.concat(
            files[bytes4(keccak256("USDK"))].data,
            files[bytes4(keccak256("ORKI"))].data,
            files[bytes4(keccak256("geist"))].data,
            files[bytes4(keccak256(abi.encodePacked(coll)))].data
        );

        //emit log_named_uint("data length", data.length);

        pointer = SSTORE2.write(data);
    }

    function _deployFixedAssetReader(bytes32 _salt, string memory coll) internal {
        bytes4[] memory sigs = new bytes4[](4);
        sigs[0] = bytes4(keccak256("USDK"));
        sigs[1] = bytes4(keccak256("ORKI"));
        sigs[2] = bytes4(keccak256("geist"));
        sigs[3] = bytes4(keccak256(abi.encodePacked(coll)));

        FixedAssetReader.Asset[] memory FixedAssets = new FixedAssetReader.Asset[](4);
        FixedAssets[0] = FixedAssetReader.Asset(
            uint128(files[bytes4(keccak256("USDK"))].start), uint128(files[bytes4(keccak256("USDK"))].end)
        );
        FixedAssets[1] = FixedAssetReader.Asset(
            uint128(files[bytes4(keccak256("ORKI"))].start), uint128(files[bytes4(keccak256("ORKI"))].end)
        );
        FixedAssets[2] = FixedAssetReader.Asset(
            uint128(files[bytes4(keccak256("geist"))].start), uint128(files[bytes4(keccak256("geist"))].end)
        );
        FixedAssets[3] = FixedAssetReader.Asset(
            uint128(files[bytes4(keccak256(abi.encodePacked(coll)))].start), uint128(files[bytes4(keccak256(abi.encodePacked(coll)))].end)
        );

        initializedFixedAssetReader = new FixedAssetReader{salt: _salt}(pointer, sigs, FixedAssets);
    }
}
