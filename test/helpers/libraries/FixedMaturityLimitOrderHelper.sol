// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {FixedMaturityLimitOrder} from "@src/market/libraries/OfferLibrary.sol";

library FixedMaturityLimitOrderHelper {
    function pointOffer(uint256 tenor, uint256 apr) public view returns (FixedMaturityLimitOrder memory) {
        uint256[] memory maturities = new uint256[](1);
        uint256[] memory aprs = new uint256[](1);

        maturities[0] = block.timestamp + tenor;
        aprs[0] = apr;

        return FixedMaturityLimitOrder({maturities: maturities, aprs: aprs});
    }

    function customOffer(uint256 tenor1, uint256 apr1, uint256 tenor2, uint256 apr2)
        public
        view
        returns (FixedMaturityLimitOrder memory)
    {
        uint256[] memory maturities = new uint256[](2);
        uint256[] memory aprs = new uint256[](2);

        maturities[0] = block.timestamp + tenor1;
        maturities[1] = block.timestamp + tenor2;

        aprs[0] = apr1;
        aprs[1] = apr2;

        return FixedMaturityLimitOrder({maturities: maturities, aprs: aprs});
    }

    function customOffer(uint256 tenor1, uint256 apr1, uint256 tenor2, uint256 apr2, uint256 tenor3, uint256 apr3)
        public
        view
        returns (FixedMaturityLimitOrder memory)
    {
        uint256[] memory maturities = new uint256[](3);
        uint256[] memory aprs = new uint256[](3);

        maturities[0] = block.timestamp + tenor1;
        maturities[1] = block.timestamp + tenor2;
        maturities[2] = block.timestamp + tenor3;

        aprs[0] = apr1;
        aprs[1] = apr2;
        aprs[2] = apr3;

        return FixedMaturityLimitOrder({maturities: maturities, aprs: aprs});
    }

    function normalOffer() public view returns (FixedMaturityLimitOrder memory) {
        uint256[] memory tenors = new uint256[](6);
        uint256[] memory aprs = new uint256[](6);

        aprs[0] = 0.01e18;
        aprs[1] = 0.02e18;
        aprs[2] = 0.03e18;
        aprs[3] = 0.04e18;
        aprs[4] = 0.05e18;
        aprs[5] = 0.06e18;

        tenors[0] = 30 days;
        tenors[1] = 60 days;
        tenors[2] = 90 days;
        tenors[3] = 120 days;
        tenors[4] = 150 days;
        tenors[5] = 180 days;

        return _fromTenors(tenors, aprs);
    }

    function flatOffer() public view returns (FixedMaturityLimitOrder memory) {
        uint256[] memory tenors = new uint256[](6);
        uint256[] memory aprs = new uint256[](6);

        aprs[0] = 0.04e18;
        aprs[1] = 0.04e18;
        aprs[2] = 0.04e18;
        aprs[3] = 0.04e18;
        aprs[4] = 0.04e18;
        aprs[5] = 0.04e18;

        tenors[0] = 30 days;
        tenors[1] = 60 days;
        tenors[2] = 90 days;
        tenors[3] = 120 days;
        tenors[4] = 150 days;
        tenors[5] = 180 days;

        return _fromTenors(tenors, aprs);
    }

    function invertedOffer() public view returns (FixedMaturityLimitOrder memory) {
        uint256[] memory tenors = new uint256[](6);
        uint256[] memory aprs = new uint256[](6);

        aprs[0] = 0.05e18;
        aprs[1] = 0.04e18;
        aprs[2] = 0.03e18;
        aprs[3] = 0.02e18;
        aprs[4] = 0.01e18;
        aprs[5] = 0.005e18;

        tenors[0] = 30 days;
        tenors[1] = 60 days;
        tenors[2] = 90 days;
        tenors[3] = 120 days;
        tenors[4] = 150 days;
        tenors[5] = 180 days;

        return _fromTenors(tenors, aprs);
    }

    function humpedOffer() public view returns (FixedMaturityLimitOrder memory) {
        uint256[] memory tenors = new uint256[](6);
        uint256[] memory aprs = new uint256[](6);

        aprs[0] = 0.01e18;
        aprs[1] = 0.02e18;
        aprs[2] = 0.03e18;
        aprs[3] = 0.02e18;
        aprs[4] = 0.01e18;
        aprs[5] = 0.005e18;

        tenors[0] = 30 days;
        tenors[1] = 60 days;
        tenors[2] = 90 days;
        tenors[3] = 120 days;
        tenors[4] = 150 days;
        tenors[5] = 180 days;

        return _fromTenors(tenors, aprs);
    }

    function steepOffer() public view returns (FixedMaturityLimitOrder memory) {
        uint256[] memory tenors = new uint256[](6);
        uint256[] memory aprs = new uint256[](6);

        aprs[0] = 0.01e18;
        aprs[1] = 0.05e18;
        aprs[2] = 0.06e18;
        aprs[3] = 0.07e18;
        aprs[4] = 0.08e18;
        aprs[5] = 0.09e18;

        tenors[0] = 30 days;
        tenors[1] = 60 days;
        tenors[2] = 90 days;
        tenors[3] = 120 days;
        tenors[4] = 150 days;
        tenors[5] = 180 days;

        return _fromTenors(tenors, aprs);
    }

    function marketOffer() public view returns (FixedMaturityLimitOrder memory) {
        return normalOffer();
    }

    function getRandomOffer(uint256 seed) public view returns (FixedMaturityLimitOrder memory) {
        if (seed % 5 == 0) {
            return normalOffer();
        } else if (seed % 5 == 1) {
            return flatOffer();
        } else if (seed % 5 == 2) {
            return invertedOffer();
        } else if (seed % 5 == 3) {
            return humpedOffer();
        } else {
            return steepOffer();
        }
    }

    function maturitiesArray(uint256 maturity1, uint256 maturity2) public pure returns (uint256[] memory) {
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = maturity1;
        maturities[1] = maturity2;
        return maturities;
    }

    function maturitiesArray(uint256 maturity1, uint256 maturity2, uint256 maturity3)
        public
        pure
        returns (uint256[] memory)
    {
        uint256[] memory maturities = new uint256[](3);
        maturities[0] = maturity1;
        maturities[1] = maturity2;
        maturities[2] = maturity3;
        return maturities;
    }

    function maturitiesArray(uint256 maturity1, uint256 maturity2, uint256 maturity3, uint256 maturity4)
        public
        pure
        returns (uint256[] memory)
    {
        uint256[] memory maturities = new uint256[](4);
        maturities[0] = maturity1;
        maturities[1] = maturity2;
        maturities[2] = maturity3;
        maturities[3] = maturity4;
        return maturities;
    }

    function aprsArray(uint256 apr1, uint256 apr2) public pure returns (uint256[] memory) {
        uint256[] memory aprs = new uint256[](2);
        aprs[0] = apr1;
        aprs[1] = apr2;
        return aprs;
    }

    function aprsArray(uint256 apr1, uint256 apr2, uint256 apr3) public pure returns (uint256[] memory) {
        uint256[] memory aprs = new uint256[](3);
        aprs[0] = apr1;
        aprs[1] = apr2;
        aprs[2] = apr3;
        return aprs;
    }

    function aprsArray(uint256 apr1, uint256 apr2, uint256 apr3, uint256 apr4) public pure returns (uint256[] memory) {
        uint256[] memory aprs = new uint256[](4);
        aprs[0] = apr1;
        aprs[1] = apr2;
        aprs[2] = apr3;
        aprs[3] = apr4;
        return aprs;
    }

    function _fromTenors(uint256[] memory tenors, uint256[] memory aprs)
        private
        view
        returns (FixedMaturityLimitOrder memory)
    {
        uint256[] memory maturities = new uint256[](tenors.length);
        for (uint256 i = 0; i < tenors.length; i++) {
            maturities[i] = block.timestamp + tenors[i];
        }

        return FixedMaturityLimitOrder({maturities: maturities, aprs: aprs});
    }
}
