// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {StringFormatting} from "test/Utils/StringFormatting.sol";
import {Accounts} from "test/TestContracts/Accounts.sol";
import {ERC20Faucet} from "test/TestContracts/ERC20Faucet.sol";
import {ETH_GAS_COMPENSATION} from "src/Dependencies/Constants.sol";
import {IBorrowerOperations} from "src/Interfaces/IBorrowerOperations.sol";
import "src/AddressesRegistry.sol";
import "src/ActivePool.sol";
import "src/BoldToken.sol";
import "src/BorrowerOperations.sol";
import "src/CollSurplusPool.sol";
import "src/DefaultPool.sol";
import "src/GasPool.sol";
import "src/HintHelpers.sol";
import "src/MultiTroveGetter.sol";
import "src/SortedTroves.sol";
import "src/StabilityPool.sol";
import "test/TestContracts/BorrowerOperationsTester.t.sol";
import "test/TestContracts/TroveManagerTester.t.sol";
import "src/TroveNFT.sol";
import "src/CollateralRegistry.sol";
import "test/TestContracts/MockInterestRouter.sol";
import "test/TestContracts/PriceFeedTestnet.sol";
import "./MetadataDeployment.sol";
import "src/Zappers/WETHZapper.sol";
import "src/Zappers/GasCompZapper.sol";
import "src/Zappers/LeverageLSTZapper.sol";
import "src/Zappers/LeverageWETHZapper.sol";
import {WETHTester} from "test/TestContracts/WETHTester.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {QuillAccessManagerUpgradeable} from "src/Quill/QuillAccessManagerUpgradeable.sol";
import {QuillSequencerSentinelMainnet} from "src/Quill/SequencerSentinel/Mainnet.sol";
import {QuillSequencerSentinel} from "src/Quill/SequencerSentinel/Scroll.sol";

abstract contract DeployQuillBase is Script, StdCheats, MetadataDeployment {
    using Strings for *;
    using StringFormatting for *;

    uint256 constant INITIAL_TROVE_CCR_MARGIN = 102 * _1pct;
    uint256 constant WETH_BORROW_CAP = 10_000_000 ether;
    uint256 constant WEETH_BORROW_CAP = 5_000_000 ether;
    uint256 constant WSTETH_BORROW_CAP = 5_000_000 ether;
    uint256 constant SCROLL_BORROW_CAP = 500_000 ether;
    uint256 constant UNLIMITED_BORROW_CAP = type(uint256).max;

    address deployer;
    Options upgradeOptions;

    struct Contracts {
        IAddressesRegistry addressesRegistry;
        IActivePool activePool;
        IBorrowerOperations borrowerOperations;
        ICollSurplusPool collSurplusPool;
        IDefaultPool defaultPool;
        ISortedTroves sortedTroves;
        IStabilityPool stabilityPool;
        ITroveManager troveManager;
        ITroveNFT troveNFT;
        MetadataNFT metadataNFT;
        IPriceFeed priceFeed;
        GasPool gasPool;
        IInterestRouter interestRouter;
        IERC20Metadata collToken;
        WETHZapper wethZapper;
        GasCompZapper gasCompZapper;
        ILeverageZapper leverageZapper;
        ISequencerSentinel sequencerSentinel;
    }

    struct Coll {
        IERC20Metadata token;
        IPriceFeed priceFeed;
    }

    struct Branch {
        address activePool;
        address borrowerOperations;
        address collSurplusPool;
        address defaultPool;
        address sortedTroves;
        address stabilityPool;
        address troveManager;
        address troveNFT;
        address metadataNFT;
        address priceFeed;
        address gasPool;
        address interestRouter;
    }

    struct Zappers {
        WETHZapper wethZapper;
        GasCompZapper gasCompZapper;
    }

    struct TroveManagerParams {
        uint256 CCR;
        uint256 MCR;
        uint256 SCR;
        uint256 BCR;
        uint256 LIQUIDATION_PENALTY_SP;
        uint256 LIQUIDATION_PENALTY_REDISTRIBUTION;
        uint256 MIN_DEBT;
        uint256 SP_YIELD_SPLIT;
        uint256 minAnnualInterestRate;
        uint256 branchCap;
    }

    struct DemoTroveParams {
        uint256 collIndex;
        uint256 owner;
        uint256 ownerIndex;
        uint256 coll;
        uint256 debt;
        uint256 annualInterestRate;
    }

    struct DeploymentResult {
        Contracts[] contractsArray;
        ICollateralRegistry collateralRegistry;
        IBoldToken boldToken;
        HintHelpers hintHelpers;
        MultiTroveGetter multiTroveGetter;
        QuillAccessManagerUpgradeable quillAccessManager;
        ISequencerSentinel sequencerSentinel;
    }

    function _getBranchContractsJson(Contracts memory c) internal pure returns (string memory) {
        return string.concat(
            "{",
            string.concat(
                // Avoid stack too deep by chunking concats
                string.concat(
                    string.concat('"addressesRegistry":"', address(c.addressesRegistry).toHexString(), '",'),
                    string.concat('"activePool":"', address(c.activePool).toHexString(), '",'),
                    string.concat('"borrowerOperations":"', address(c.borrowerOperations).toHexString(), '",'),
                    string.concat('"collSurplusPool":"', address(c.collSurplusPool).toHexString(), '",')
                ),
                string.concat(
                    string.concat('"defaultPool":"', address(c.defaultPool).toHexString(), '",'),
                    string.concat('"sortedTroves":"', address(c.sortedTroves).toHexString(), '",'),
                    string.concat('"stabilityPool":"', address(c.stabilityPool).toHexString(), '",'),
                    string.concat('"troveManager":"', address(c.troveManager).toHexString(), '",')
                ),
                string.concat(
                    string.concat('"troveNFT":"', address(c.troveNFT).toHexString(), '",'),
                    string.concat('"metadataNFT":"', address(c.metadataNFT).toHexString(), '",'),
                    string.concat('"priceFeed":"', address(c.priceFeed).toHexString(), '",'),
                    string.concat('"gasPool":"', address(c.gasPool).toHexString(), '",')
                ),
                string.concat(
                    string.concat('"interestRouter":"', address(c.interestRouter).toHexString(), '",'),
                    string.concat('"wethZapper":"', address(c.wethZapper).toHexString(), '",'),
                    string.concat('"gasCompZapper":"', address(c.gasCompZapper).toHexString(), '",'),
                    string.concat('"leverageZapper":"', address(c.leverageZapper).toHexString(), '",')
                ),
                string.concat(
                    string.concat('"collToken":"', address(c.collToken).toHexString(), '"') // no comma
                )
            ),
            "}"
        );
    }

    function _getDeploymentConstants() internal pure returns (string memory) {
        return string.concat(
            "{",
            string.concat(
                string.concat('"ETH_GAS_COMPENSATION":"', ETH_GAS_COMPENSATION.toString(), '",'),
                string.concat('"INTEREST_RATE_ADJ_COOLDOWN":"', INTEREST_RATE_ADJ_COOLDOWN.toString(), '",'),
                string.concat('"MAX_ANNUAL_INTEREST_RATE":"', MAX_ANNUAL_INTEREST_RATE.toString(), '",'),
                string.concat('"UPFRONT_INTEREST_PERIOD":"', UPFRONT_INTEREST_PERIOD.toString(), '"') // no comma
            ),
            "}"
        );
    }

    function _getManifestJson(DeploymentResult memory deployed) internal pure returns (string memory) {
        string[] memory branches = new string[](deployed.contractsArray.length);

        // Poor man's .map()
        for (uint256 i = 0; i < branches.length; ++i) {
            branches[i] = _getBranchContractsJson(deployed.contractsArray[i]);
        }

        return string.concat(
            "{",
            string.concat(
                string.concat('"constants":', _getDeploymentConstants(), ","),
                string.concat('"collateralRegistry":"', address(deployed.collateralRegistry).toHexString(), '",'),
                string.concat('"boldToken":"', address(deployed.boldToken).toHexString(), '",'),
                string.concat('"hintHelpers":"', address(deployed.hintHelpers).toHexString(), '",')
            ),
            string.concat(
                string.concat('"multiTroveGetter":"', address(deployed.multiTroveGetter).toHexString(), '",'),
                string.concat('"quillAccessManager":"', address(deployed.quillAccessManager).toHexString(), '",'),
                string.concat('"sequencerSentinel":"', address(deployed.sequencerSentinel).toHexString(), '",')
            ),
            string.concat('"branches":[', branches.join(","), "]"),
            "}"
        );
    }

    // See: https://solidity-by-example.org/app/create2/
    function getBytecode(bytes memory _creationCode, address _addressesRegistry) public pure returns (bytes memory) {
        return abi.encodePacked(_creationCode, abi.encode(_addressesRegistry));
    }

    function getBytecode(
        bytes memory _creationCode,
        address _addressesRegistry,
        TroveManagerParams memory troveManagerParams
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            _creationCode,
            abi.encode(
                _addressesRegistry,
                troveManagerParams.CCR,
                troveManagerParams.MCR,
                troveManagerParams.SCR,
                troveManagerParams.BCR,
                troveManagerParams.MIN_DEBT,
                troveManagerParams.minAnnualInterestRate,
                troveManagerParams.LIQUIDATION_PENALTY_SP,
                troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION
            )
        );
    }

    function getBytecode(bytes memory _creationCode, address _addressesRegistry, uint256 newVar)
        public
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(_creationCode, abi.encode(_addressesRegistry, newVar));
    }

    // Solidity...
    function _asIERC20Array(ERC20Faucet[] memory erc20faucets) internal pure returns (IERC20Metadata[] memory erc20s) {
        assembly {
            erc20s := erc20faucets
        }
    }

    function formatAmount(uint256 amount, uint256 decimals, uint256 digits) internal pure returns (string memory) {
        if (digits > decimals) {
            digits = decimals;
        }

        uint256 scaled = amount / (10 ** (decimals - digits));
        string memory whole = Strings.toString(scaled / (10 ** digits));

        if (digits == 0) {
            return whole;
        }

        string memory fractional = Strings.toString(scaled % (10 ** digits));
        for (uint256 i = bytes(fractional).length; i < digits; i++) {
            fractional = string.concat("0", fractional);
        }
        return string.concat(whole, ".", fractional);
    }

    function _enoughBalanceForDeploymentSafetyCheck(Coll[] memory colls, uint256[] memory mindebts) internal {
        for (uint8 i = 0; i < colls.length; i++) {
            (uint256 _tokenPrice,) = colls[i].priceFeed.fetchPrice();
            uint256 _tokenDecimals = colls[i].token.decimals();
            uint256 _tokenBalance = colls[i].token.balanceOf(deployer);

            uint256 _tokenBalanceInUSD = (_tokenBalance * _tokenPrice) / (10 ** _tokenDecimals);
            uint256 _minRequiredBalanceInUSD = mindebts[i] * 150 / 100 * INITIAL_TROVE_CCR_MARGIN / _100pct;
            if (_tokenBalanceInUSD < _minRequiredBalanceInUSD) {
                uint256 _minRequiredBalanceInToken = _minRequiredBalanceInUSD * (10 ** _tokenDecimals) / _tokenPrice;
                console.log(
                    "Need %i %s to open a zombie trove. %s found",
                    _minRequiredBalanceInToken,
                    colls[i].token.symbol(),
                    _tokenBalance
                );
                revert("Not enough balance");
            }
        }
    }

    function _calcMinimumAmountOfCollateral(Contracts memory contracts, uint256 minDebt) internal returns (uint256) {
        (uint256 _tokenPrice,) = contracts.priceFeed.fetchPrice();
        uint256 _tokenDecimals = contracts.collToken.decimals();
        uint256 ccr = contracts.troveManager.CCR();
        uint256 _minRequiredBalanceInUSD = minDebt * ccr / _100pct * INITIAL_TROVE_CCR_MARGIN / _100pct;
        uint256 _minRequiredTokenAmount = (_minRequiredBalanceInUSD * (10 ** _tokenDecimals)) / _tokenPrice;
        return _minRequiredTokenAmount;
    }

    function _createZombieTrovesAsDeployer_OpeningTroves(DeploymentResult memory _deploymentContracts) internal {
        for (uint256 i = 0; i < _deploymentContracts.contractsArray.length; i++) {
            Contracts memory contracts = _deploymentContracts.contractsArray[i];
            uint256 minDebt = contracts.troveManager.MIN_DEBT();
            uint256 interestRate = contracts.troveManager.minAnnualInterestRate();
            uint256 minColl = _calcMinimumAmountOfCollateral(contracts, minDebt);

            IERC20 collToken = IERC20(contracts.collToken);
            IERC20 wethToken = IERC20(contracts.addressesRegistry.WETH());

            if (collToken == wethToken) {
                wethToken.approve(address(contracts.borrowerOperations), minColl + ETH_GAS_COMPENSATION);
            } else {
                wethToken.approve(address(contracts.borrowerOperations), ETH_GAS_COMPENSATION);
                collToken.approve(address(contracts.borrowerOperations), minColl);
            }

            IBorrowerOperations(contracts.borrowerOperations).openTrove(
                deployer, //     _owner
                0, //         _ownerIndex
                minColl, //               _collAmount
                minDebt, //               _boldAmount
                0, //                        _upperHint
                0, //                        _lowerHint
                interestRate,
                type(uint256).max, //        _maxUpfrontFee
                address(0), //               _addManager
                address(0), //               _removeManager
                address(0) //                _receiver
            );
        }
    }

    function _depositInStabilityPools(DeploymentResult memory _deploymentContracts) internal {
        for (uint256 i = 0; i < _deploymentContracts.contractsArray.length; i++) {
            Contracts memory contracts = _deploymentContracts.contractsArray[i];
            IStabilityPool _sp = IStabilityPool(contracts.stabilityPool);
            _deploymentContracts.boldToken.approve(address(_sp), DECIMAL_PRECISION);
            _sp.provideToSP(DECIMAL_PRECISION, false);
        }
    }

    function _createZombieTrovesAsDeployer_RedeemingUSDq(DeploymentResult memory _deploymentContracts) internal {
        uint256 resultingUSDqBalance = _deploymentContracts.boldToken.balanceOf(deployer);
        uint256 maxFeePct =
            _deploymentContracts.collateralRegistry.getRedemptionRateForRedeemedAmount(resultingUSDqBalance);

        _deploymentContracts.collateralRegistry.redeemCollateral(resultingUSDqBalance, 0, maxFeePct);
    }

    function computeUUPSProxyCreate2Address(bytes memory creationCode, bytes memory initData, Options memory opts)
        internal
        pure
        returns (address)
    {
        address targetImplementation = vm.computeCreate2Address(opts.customSalt, keccak256(creationCode));
        bytes memory bytecodeERC1967Proxy =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(targetImplementation, initData));
        return vm.computeCreate2Address(opts.customSalt, keccak256(bytecodeERC1967Proxy));
    }
}
