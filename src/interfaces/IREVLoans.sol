pragma solidity ^0.8.0;

interface IREVLoans {
    function borrow(
        uint256 revnetId,
        uint256 tokenCount,
        uint256 minExpectedLoanAmount
    )
        external
        view
        returns (uint256);
}
