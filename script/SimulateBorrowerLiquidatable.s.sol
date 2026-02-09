// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {RESERVED_ID} from "@src/market/libraries/actions/SellCreditMarket.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {BuyCreditLimitParams} from "@src/market/libraries/actions/BuyCreditLimit.sol";
import {DepositParams} from "@src/market/libraries/actions/Deposit.sol";
import {SellCreditMarketParams} from "@src/market/libraries/actions/SellCreditMarket.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract GetCalldataScript is Script {
    using Tenderly for *;

    Tenderly.Client tenderly;

    function setUp() public {
        string memory accountSlug = vm.envString("TENDERLY_ACCOUNT_NAME");
        string memory projectSlug = vm.envString("TENDERLY_PROJECT_NAME");
        string memory accessKey = vm.envString("TENDERLY_ACCESS_KEY");

        tenderly.initialize(accountSlug, projectSlug, accessKey);
    }

    function run() external {
        console.log("GetCalldata...");

        address size = vm.envAddress("SIZE_ADDRESS");
        address borrower = vm.envAddress("BORROWER");
        address lender = vm.envAddress("LENDER");

        console.log("size", size);
        console.log("borrower", borrower);
        console.log("lender", lender);

        Tenderly.VirtualTestnet memory vnet =
            tenderly.createVirtualTestnet(string.concat("vnet-", vm.toString(block.chainid)), 1_000_000 + block.chainid);

        IERC20Metadata underlyingBorrowToken = ISize(size).data().underlyingBorrowToken;

        tenderly.sendTransaction(
            vnet.id, borrower, address(underlyingBorrowToken), abi.encodeCall(IERC20.approve, (address(size), 2000e18))
        );
        tenderly.sendTransaction(
            vnet.id,
            borrower,
            address(size),
            abi.encodeCall(
                ISize.deposit, (DepositParams({token: address(underlyingBorrowToken), amount: 2000e18, to: borrower}))
            )
        );
        ISize sizeContract = ISize(size);
        uint256 maturity = sizeContract.riskConfig().maturities[1];
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        uint256[] memory aprs = new uint256[](1);
        aprs[0] = 0.05e18;
        tenderly.sendTransaction(
            vnet.id,
            lender,
            address(size),
            abi.encodeCall(ISize.buyCreditLimit, (BuyCreditLimitParams({maturities: maturities, aprs: aprs})))
        );
        tenderly.sendTransaction(
            vnet.id,
            lender,
            address(size),
            abi.encodeCall(
                ISize.sellCreditMarket,
                (
                    SellCreditMarketParams({
                        lender: lender,
                        creditPositionId: RESERVED_ID,
                        maturity: maturity,
                        amount: 1000e6,
                        deadline: type(uint256).max,
                        maxAPR: type(uint256).max,
                        exactAmountIn: false,
                        collectionId: RESERVED_ID,
                        rateProvider: address(0)
                    })
                )
            )
        );
    }
}
