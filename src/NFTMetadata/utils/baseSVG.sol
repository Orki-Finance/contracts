//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {svg} from "./SVG.sol";
import {utils, LibString, numUtils} from "./Utils.sol";
import "./FixedAssets.sol";

library baseSVG {
    string constant GEIST = 'style="font-family: Denim" ';
    string constant BLACK = "#0D0B0C";
    string constant ORANGE_SUPER_LIGHT = "#FFFFFF";

    function _svgProps() internal pure returns (string memory) {
        return string.concat(
            svg.prop("width", "300"),
            svg.prop("height", "484"),
            svg.prop("viewBox", "0 0 300 484"),
            svg.prop("style", "background:none")
        );
    }

    function _baseElements(FixedAssetReader _assetReader) internal view returns (string memory) {
        return string.concat(
            svg.rect(
                string.concat(
                    svg.prop("fill", BLACK),
                    svg.prop("rx", "8"),
                    svg.prop("width", "300"),
                    svg.prop("height", "484")
                )
            ),
            _styles(_assetReader),
            _leverageLogo(_assetReader),
            _boldLogo(_assetReader),
            _staticTextEls()
        );
    }

    function _styles(FixedAssetReader _assetReader) private view returns (string memory) {
        return svg.el(
            "style",
            utils.NULL,
            string.concat(
                '@font-face { font-family: "Denim"; src: url("data:font/woff2;utf-8;base64,',
                _assetReader.readAsset(bytes4(keccak256("geist"))),
                '"); }'
            )
        );
    }

    function _leverageLogo(FixedAssetReader _assetReader) internal view returns (string memory) {
        return svg.el(
            "image",
            string.concat(
                svg.prop("x", "13"),
                svg.prop("y", "15"),
                svg.prop("width", "24"),
                svg.prop("height", "24"),
                svg.prop(
                    "href",
                    string.concat("data:image/svg+xml;base64,", _assetReader.readAsset(bytes4(keccak256("ORKI"))))
                )
            )
        );
    }

    function _boldLogo(FixedAssetReader _assetReader) internal view returns (string memory) {
        return svg.el(
            "image",
            string.concat(
                svg.prop("x", "264"),
                svg.prop("y", "373.5"),
                svg.prop("width", "20"),
                svg.prop("height", "20"),
                svg.prop(
                    "href",
                    string.concat("data:image/svg+xml;base64,", _assetReader.readAsset(bytes4(keccak256("USDK"))))
                )
            )
        );
    }

    function _staticTextEls() internal pure returns (string memory) {
        return string.concat(
            svg.text(
                string.concat(
                    GEIST,
                    svg.prop("x", "16"),
                    svg.prop("y", "358"),
                    svg.prop("font-size", "14"),
                    svg.prop("fill", "white")
                ),
                "Collateral"
            ),
            svg.text(
                string.concat(
                    GEIST,
                    svg.prop("x", "16"),
                    svg.prop("y", "389"),
                    svg.prop("font-size", "14"),
                    svg.prop("fill", "white")
                ),
                "Debt"
            ),
            svg.text(
                string.concat(
                    GEIST,
                    svg.prop("x", "16"),
                    svg.prop("y", "420"),
                    svg.prop("font-size", "14"),
                    svg.prop("fill", "white")
                ),
                "Interest Rate"
            ),
            svg.text(
                string.concat(
                    GEIST,
                    svg.prop("x", "265"),
                    svg.prop("y", "422"),
                    svg.prop("font-size", "20"),
                    svg.prop("fill", "white")
                ),
                "%"
            ),
            svg.text(
                string.concat(
                    GEIST,
                    svg.prop("x", "16"),
                    svg.prop("y", "462"),
                    svg.prop("font-size", "14"),
                    svg.prop("fill", "white")
                ),
                "Owner"
            )
        );
    }

    function _formattedDynamicEl(string memory _value, uint256 _x, uint256 _y) internal pure returns (string memory) {
        return svg.text(
            string.concat(
                GEIST,
                svg.prop("text-anchor", "end"),
                svg.prop("x", LibString.toString(_x)),
                svg.prop("y", LibString.toString(_y)),
                svg.prop("font-size", "20"),
                svg.prop("fill", "white")
            ),
            _value
        );
    }

    function _formattedIdEl(string memory _id) internal pure returns (string memory) {
        return svg.text(
            string.concat(
                GEIST,
                svg.prop("text-anchor", "end"),
                svg.prop("x", "284"),
                svg.prop("y", "33"),
                svg.prop("font-size", "14"),
                svg.prop("fill", "white")
            ),
            _id
        );
    }

    function _formattedAddressEl(address _address) internal pure returns (string memory) {
        return svg.text(
            string.concat(
                GEIST,
                svg.prop("text-anchor", "end"),
                svg.prop("x", "284"),
                svg.prop("y", "462"),
                svg.prop("font-size", "14"),
                svg.prop("fill", "white")
            ),
            string.concat(
                LibString.slice(LibString.toHexStringChecksummed(_address), 0, 6),
                "...",
                LibString.slice(LibString.toHexStringChecksummed(_address), 38, 42)
            )
        );
    }

    function _collLogo(string memory _collName, FixedAssetReader _assetReader) internal view returns (string memory) {
        return svg.el(
            "image",
            string.concat(
                svg.prop("x", "264"),
                svg.prop("y", "342.5"),
                svg.prop("width", "20"),
                svg.prop("height", "20"),
                svg.prop(
                    "href",
                    string.concat(
                        "data:image/svg+xml;base64,", _assetReader.readAsset(bytes4(keccak256(bytes(_collName))))
                    )
                )
            )
        );
    }

    function _statusEl(string memory _status) internal pure returns (string memory) {
        return svg.text(
            string.concat(
                GEIST, svg.prop("x", "40"), svg.prop("y", "33"), svg.prop("font-size", "14"), svg.prop("fill", "white")
            ),
            _status
        );
    }

    function _dynamicTextEls(uint256 _debt, uint256 _coll, uint256 _annualInterestRate)
        internal
        pure
        returns (string memory)
    {
        uint8 collPrecision = _determinePrecision(_coll);

        return string.concat(
            _formattedDynamicEl(numUtils.toLocaleString(_coll, 18, collPrecision), 256, 360),
            _formattedDynamicEl(numUtils.toLocaleString(_debt, 18, 2), 256, 391),
            _formattedDynamicEl(numUtils.toLocaleString(_annualInterestRate, 16, 2), 256, 422)
        );
    }

    function _determinePrecision(uint256 _value) internal pure returns (uint8) {
        if (_value < 1e15) { // Less than 0.001
            return 4;
        } else if (_value < 1e18) { // Less than 1
            return 3;
        } else if (_value < 1e21) { // Less than 1000
            return 2;
        } else {
            return 1;
        }
    }
}
