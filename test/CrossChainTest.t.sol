//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
// CCIPLocal dùng để tạo bộ mô phỏng CCIP cho test local
// Register kèm networkdetails chưa địa chỉ hạ tầng cho mỗi fork
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
// IERC20 from ccip đc dùng để tường thích tránh gây lỗi mismatch
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
// Để đưa một token vào hệ quản trị (TokenAdminRegistry)
// => owner phải đăng kí cho phép registry quản trị token đó
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
// Nhận quyền admin role và set pool tương ứng
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
//Cung cấp chainUpdate/applyChainUpdate
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
// Khi gọi chainUpdate thì cần phải cung cấp out/inBoundRateLimiter => cần RateLimiter
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    // Tạo owner and user
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    uint256 constant SEND_VALUE = 1e5;

    // Tạo biến cho 2 fork (Sepolia vs Arb Sepolia)
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    // Khai báo biến mô phỏng CCIP cho test
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    // Tạo 2 token kiểu ReabseToken
    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    // Khai báo vault
    Vault vault;

    // Khai báo tạo 2 Pool cho sepoila và arb sepolia
    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    // Biến chứa địa chỉ hạ tầng cho từng fork
    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        // Tạo 2 fork
        sepoliaFork = vm.createSelectFork("sepolia"); // Tạo và chọn ngay Sepoila làm fork hiện tại
        arbSepoliaFork = vm.createFork("arbSepolia"); // Tạo nhưng chưa chọn fork Arb Sepolia

        // Khởi tạo bộ mô phỏng CCIP và giữ sống object qua các lần đổi fork
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork)); // Giữ sống object

        ///////////////////////////
        //      On Sepolia       //
        ///////////////////////////
        // Lấy routerAddress, rmnProxyAddress, tokenAdminRegistryAddress, registryModuleOwnerCustomAddress, chainSelector cho Sepolia.
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        // Tạo sepolia token + vault
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaToken.grantMintAndBurnRole(address(vault)); // Cấp quyền mint and burn cho vault
        // Tạo pool và truyền cấu hình hạ tầng đã lấy từ sepoliaNetworkDetails
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool)); // Cấp quyền mint and burn cho Pool

        // Đăng kí TOKEN vào hệ quản trị CCIP và gán Pool
        // Owner uỷ quyền cho Registry quản trị token
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        // Token Admin Registry chấp nhận quyền quản trị token từ owner
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        // Map Token và Pool trong Registry
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );
        vm.stopPrank();

        ///////////////////////////
        //     On Arb-Sepolia    //
        ///////////////////////////
        // CHuyển sang fork thứ 2 (Arb Sepolia)
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        // Lấy routerAddress, rmnProxyAddress, tokenAdminRegistryAddress, registryModuleOwnerCustomAddress, chainSelector cho Arb Sepolia.
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        // Tạo token arb sepolia + Pool
        arbSepoliaToken = new RebaseToken();
        // Cấu hình được lấy từ arbSepoliaNetworkDetails sẽ được truyền vào pool của Arb sepolia
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        // Cấp quyền mint and burn cho Arb Pool
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));

        // Owner uỷ quyền cho Registry quản trị token arb
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        // Token Admin Registry chấp nhận quyền quản trị token Arb
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        // Map Arb với arb pool tương ứng
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaPool)
        );
        vm.stopPrank();

        ///////////////////////////
        //     Configure Pool    //
        ///////////////////////////
        configureTokenPool(
            sepoliaFork, // cấu hình trên Sepolia
            address(sepoliaPool), // pool local (Sepolia)
            arbSepoliaNetworkDetails.chainSelector, // chain selector CCIP của Arbitrum Sepolia
            address(arbSepoliaPool), // địa chỉ pool bên Arbitrum Sepolia
            address(arbSepoliaToken) // địa chỉ token bên Arbitrum Sepolia
        );
        configureTokenPool(
            arbSepoliaFork, // cấu hình trên Arbitrum Sepolia
            address(arbSepoliaPool), // pool local (Arbitrum Sepolia)
            sepoliaNetworkDetails.chainSelector, // chain selector CCIP của Sepolia
            address(sepoliaPool), // địa chỉ pool bên Sepolia
            address(sepoliaToken) // địa chỉ token bên Sepolia
        );
    }

    // hàm này ghi cấu hình pool remote và pool local (quan trọng nhất là chainUpdate và applyChainUpdate)
    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector, // chain selector ccip của chain đích
        address remotePool, // địa chỉ pool ở chain đích
        address remoteTokenAddress // địa chỉ token ở chain đích
    ) public {
        vm.selectFork(fork); // đảm bảo đang thao tác "đúng chain" (fork) của pool local
        vm.prank(owner);
        bytes memory encodedRemotePoolAddress = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainToAdd = new TokenPool.ChainUpdate[](1);

        // Thông tin chain đích mà pool có thể giao tiếp
        chainToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector, // chain selector của chian đích
            allowed: true,
            remotePoolAddress: encodedRemotePoolAddress, // encode địa chỉ pool chain đích
            remoteTokenAddress: abi.encode(address(remoteTokenAddress)), // encode địa chỉ token chian đích
            // cấu hình hạn mức gửi nhận token
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(chainToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge, // số lượng token muốn chuyển
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        // Chọn Local Fork
        vm.selectFork(localFork);
        // 		struct EVM2AnyMessage {
        // 		bytes receiver; // abi.encode(receiver address) for dest EVM chains
        // 	    bytes data; // Data payload
        // 	    EVMTokenAmount[] tokenAmounts; // Token transfers
        // 	    address feeToken; // Address of feeToken. address(0) means you will send msg.value.
        // 	    bytes extraArgs; // Populate this with _argsToBytes(EVMExtraArgsV2)
        //      }

        // Tạo tokenAmounts cho Message, list này chỉ có một phần tử
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        // Cấu hình token Amount để truyền vào Message
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});

        // Tạo EVM Messgage
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user), // CCIP EVM→EVM yêu cầu receiver là bytes; do đó phải abi.encode địa chỉ người nhận trên chain đích. Nếu để trực tiếp address thì không khớp format.
            data: "", // data rỗng trong trường hợp này
            tokenAmounts: tokenAmounts, // đưa vào mảng token đã tạo phía trên
            feeToken: localNetworkDetails.linkAddress, // dùng Link token để làm phí
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}))
        });

        // Tính fee Token: hỏi router xem cần bao nhiêu feeToken (LINK) để route message đến remoteNetworkDetails.chainSelector với nội dung message.
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        // Trong môi trường local test, user chưa có LINK. Simulator cung cấp LINK để user trả phí.
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);
        vm.prank(user);
        // Approve cho phép router gọi transferFrom(user, ...) để lấy phí. Nếu không approve → ccipSend (hoặc router internals) revert khi router cố rút fee.
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        vm.prank(user);
        // cho phép router (hoặc contract trung gian CCIP) rút amountToBridge token từ ví user.
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        // Lấy balance trước khi gửi
        uint256 localBalanceBefore = localToken.balanceOf(user);

        vm.prank(user);
        // User gọi ccip để gửi message
        /**
         * CCIP:
         * Thu phí LINK bằng transferFrom(user, ...).
         * Thu token amountToBridge từ user (bằng transferFrom hoặc qua pool).
         * Gọi pool local lockOrBurn (pool sẽ burn hoặc lock token). Trong RebaseTokenPool bạn burn.
         * Lưu message + destPoolData (do lockOrBurn trả về) để gửi đến chain đích.
         * Quan trọng: việc token bị trừ khỏi user có thể thực hiện bởi router hoặc pool tuỳ impl CCIP, nhưng approve phải đúng cho địa chỉ router (hoặc contract được router chuyển token đến).
         */
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        // Lấy balance sau khi gửi
        uint256 localBalanceAfter = localToken.balanceOf(user);
        // kiểm tra lượng token của user ở source chain
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);
        // lấy interest từ chain source
        // uint256 localUserInterestRate = localToken.getUserInterestRate(user);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);
        vm.selectFork(localFork);
        // Lệnh này giúp chuyển môi trường thực thi từ chain nguồn sang chain đích.
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        // kiểm tra lượng token của user ở dest chain
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);
        // lấy interest từ chain đích
        // uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
        // kiểm tra xem interest có giữ nguyên không
        // assertEq(remoteUserInterestRate, localUserInterestRate);
    }

    function testBridgeAllTokens() public {
        // chọn LocalFork
        vm.selectFork(sepoliaFork);
        // cấp token cho user để test
        vm.deal(user, SEND_VALUE);
        // giả định user là người gọi
        vm.startPrank(user);
        // user deposit vào vault
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        // kiểm tra tài khoản của user
        assertEq(IERC20(address(sepoliaToken)).balanceOf(user), SEND_VALUE);
        vm.stopPrank();
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
    }
}
