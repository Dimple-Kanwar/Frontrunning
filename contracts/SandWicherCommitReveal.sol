// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IBEP20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


interface WBNB is IERC20 {
    function deposit() external payable;
    function withdraw(uint) external;
}

interface IPancakeRouter02 {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface ISandWicher {
    struct SimulationResult {                 
        uint256 expectedBuy;
        uint256 balanceBeforeBuy;
        uint256 balanceAfterBuy;
        uint256 balanceBeforeSell;
        uint256 balanceAfterSell;
        uint256 expectedSell;
    }
}

contract SandwichAttack is ISandWicher {
    address private owner;
    mapping(address => uint256) private _buyBlock;
    bool public checkBot = true;

    // Struct is used to store the commit details
    struct Commit {
        bytes32 dataHash;
        uint commitTime;
        bool revealed;
        string method;
    }

    // Mapping to store the commit details with address
    mapping(address => Commit) commits;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Commit Transaction data hash
     */
    function commitTx(bytes32 _dataHash, string memory _method) external onlyOwner {
        Commit storage commit = commits[msg.sender];
        require(commit.commitTime == 0, "Already committed");
        commit.dataHash = _dataHash;
        commit.commitTime = block.timestamp;
        commit.revealed = false;
        commit.method = _method;
    }
    
    /* 
        Function to get the commit details. It returns a tuple of (dataHash, commitTime, revealStatus, transaction method);
    */
    function getData() public view onlyOwner returns(bytes32, uint, bool, string memory) {
        Commit memory commit = commits[msg.sender];
        require(commit.commitTime != 0, "Not committed yet");
        return (commit.dataHash, commit.commitTime, commit.revealed, commit.method);        
    }

    /* 
        Function to reveal the commit and get the tokens. 
        Users can get reveal data only if the game is active and they have committed a solutionHash and not revealed yet.
        It generates an keccak256(msg.sender + data + secret) and checks it with the previously commited hash.  
        Front runners will not be able to pass this check since the msg.sender is different.
        Then the actual solution is checked using keccak256(solution), if the solution matches, the winner is declared, 
        the game is ended and the reward amount is sent to the winner.
    */
    function revealTx (bytes calldata _data, string memory _secret, string memory method) external onlyOwner {
        Commit storage commit = commits[msg.sender];
        require(commit.commitTime != 0, "Not committed yet");
        require(!commit.revealed, "Already commited and revealed");
        bytes32 dataHash = keccak256(
            abi.encodePacked(Strings.toHexString(msg.sender), _data, _secret)
        );
        require(dataHash == commit.dataHash, "Hash doesn't match");
        if (Strings.equal(method,"buyToken")) {
            (
                address router,
                uint256 amountIn,
                uint256 amountOutMin,
                address[] memory path
            ) = abi.decode(_data, (address, uint256, uint256, address[]));
            _buy(router, amountIn, amountOutMin, path);
        } else if(Strings.equal(method,"sellToken")) {
            (address router, address[] memory path,uint256 amountOutMin) = abi.decode(
                _data,
                (address, address[],uint256)
            );
            _sell(router, path, amountOutMin);
        } else {
            revert();
        }
    }

    function simulate(bytes calldata _buydata, bytes calldata _selldata)
        external
        onlyOwner
        returns (SimulationResult memory result)
        {
            address[] memory path;
            address router;
            uint256 amountIn;
            uint256 amountOutMin;
            // Buy
            (router, amountIn, amountOutMin, path) = abi.decode(
                _buydata,
                (address, uint256, uint256, address[])
            );

            IERC20 toToken = IERC20(path[path.length - 1]);

            uint256 balanceBeforeBuy = toToken.balanceOf(address(this));

            uint256 expectedBuy = getAmountsOut(router, amountIn, path);

            _buy(router, amountIn, amountOutMin, path);

            uint256 balanceAfterBuy = toToken.balanceOf(address(this));

            // Sell

            (router, path, amountOutMin) = abi.decode(_selldata, (address, address[], uint256));
            IERC20 fromToken = IERC20(path[path.length - 1]);

            uint256 balanceBeforeSell = fromToken.balanceOf(address(this));
            amountIn = IERC20(path[0]).balanceOf(address(this));
            uint256 expectedSell = getAmountsOut(router, amountIn, path);
            _sell(router, path, amountOutMin);

            uint256 balanceAfterSell = fromToken.balanceOf(address(this));

            return
                SimulationResult({
                    expectedBuy: expectedBuy,
                    balanceBeforeBuy: balanceBeforeBuy,
                    balanceAfterBuy: balanceAfterBuy,
                    balanceBeforeSell: balanceBeforeSell,
                    balanceAfterSell: balanceAfterSell,
                    expectedSell: expectedSell
                });
        }
    
    
    
    function _approve(
        IERC20 token,
        address router,
        uint256 amountIn
    ) internal {
        if (token.allowance(address(this), router) < amountIn) {
            // approving the tokens to be spent by router
            SafeERC20.safeApprove(token, router, amountIn);
        }
    }
    function swapAnalysis(
        address router,
        uint256 amountIn,
        address[] memory path
    ) public payable returns (bool) {
        (bool success, ) = router.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        if (success == false) {
            return false;
        } else {
            return true;
        }
    }

    function _buy(address router, uint256 amountIn, uint256 amountOutMin,address[] memory path) internal virtual {
        IERC20 fromToken = IERC20(path[0]);
        if (checkBot){
            require(_buyBlock[path[0]] != block.number, "Bad bot!");
        }
        _buyBlock[path[1]] = block.number;
        _approve(fromToken, router, amountIn);
        IPancakeRouter02(router)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                address(this),
                block.timestamp
            );
        

    }

    function _sell(address router, address[] memory path,uint256 amountOutMin) internal virtual{
        

        IERC20 fromToken = IERC20(path[0]);
        uint256 amountIn = fromToken.balanceOf(address(this));

        require(amountIn > 0, "!BAL");

        _approve(fromToken, router, amountIn);
           IPancakeRouter02(router)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                address(this),
                block.timestamp
            );
    }
 

    function getAmountsOut(
        address router,
        uint256 amountIn,
        address[] memory path
    ) internal view returns (uint256) {
        uint256[] memory amounts = IPancakeRouter02(router).getAmountsOut(
            amountIn,
            path
        );
        return amounts[amounts.length - 1];
    }

    function withdrawBNBToOwner() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function withdrawWBNB(address tokenAddress, uint256 amount) public onlyOwner {
        IBEP20 token = IBEP20(tokenAddress);
        token.transfer(msg.sender, amount);
    }

    function withdrawBEP20(address tokenAddress, uint256 amount) public onlyOwner {
        IBEP20 token = IBEP20(tokenAddress);
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance >= amount, "Insufficient contract balance.");
        token.transfer(msg.sender, amount);
    }

    function call(address payable _to, uint256 _value, bytes memory _data) external onlyOwner {
        (bool success, ) = _to.call{value: _value}(_data);
        require(success, "External call failed");
    }

    receive() external payable {}
}