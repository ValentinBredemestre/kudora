package main

import (
	"context"
	"crypto/ecdsa"
	_ "embed"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"math/big"
	"os"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
)

var (
	//go:embed contracts/build/MockUSDC.abi
	mockUSDCABIJSON string
	//go:embed contracts/build/MockUSDC.bin
	mockUSDCBin string
	//go:embed contracts/build/LocalSwapRouter.abi
	routerABIJSON string
	//go:embed contracts/build/LocalSwapRouter.bin
	routerBin string
)

type swapDeployment struct {
	MockUSDCAddress  string `json:"mock_usdc_address"`
	RouterAddress    string `json:"router_address"`
	MockUSDCDeployTx string `json:"mock_usdc_deploy_tx"`
	RouterDeployTx   string `json:"router_deploy_tx"`
	TokenSeedTx      string `json:"token_seed_tx"`
	KUDSeedTx        string `json:"kud_seed_tx"`
	TokenReserve     string `json:"token_reserve"`
	KUDReserve       string `json:"kud_reserve"`
	LocalnetOnly     bool   `json:"localnet_only"`
}

type swapResult struct {
	Account         string `json:"account"`
	RouterAddress   string `json:"router_address"`
	MockUSDCAddress string `json:"mock_usdc_address"`
	KUDIn           string `json:"kud_in"`
	MockUSDCBefore  string `json:"mock_usdc_before"`
	MockUSDCAfter   string `json:"mock_usdc_after"`
	TransactionHash string `json:"transaction_hash"`
	ReceiptStatus   string `json:"receipt_status"`
	GasUsed         uint64 `json:"gas_used"`
}

func runSwapDeploy(args []string) error {
	fs := flag.NewFlagSet("swap-deploy", flag.ContinueOnError)
	rpcURL := fs.String("rpc-url", "", "JSON-RPC endpoint")
	chainIDFlag := fs.Uint64("chain-id", 0, "expected EVM chain ID")
	senderKeyFile := fs.String("sender-key-file", "", "funded local deployer key")
	resultFile := fs.String("result-file", "", "deployment state output")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *rpcURL == "" || *chainIDFlag == 0 || *senderKeyFile == "" || *resultFile == "" {
		return errors.New("swap-deploy: --rpc-url, --chain-id, --sender-key-file, and --result-file are required")
	}

	client, ctx, cancel, err := dialClient(*rpcURL, receiptTimeout)
	if err != nil {
		return err
	}
	defer cancel()
	defer client.Close()
	chainID, err := ensureChainID(ctx, client, *chainIDFlag)
	if err != nil {
		return err
	}
	key, err := readKey(*senderKeyFile)
	if err != nil {
		return err
	}
	gasPrice, err := suggestedGasPrice(ctx, client)
	if err != nil {
		return err
	}
	mockABI, err := abi.JSON(strings.NewReader(mockUSDCABIJSON))
	if err != nil {
		return err
	}
	routerABI, err := abi.JSON(strings.NewReader(routerABIJSON))
	if err != nil {
		return err
	}

	mockAddress, mockTx, _, err := bind.DeployContract(
		newTransactor(ctx, key, chainID, gasPrice, nil),
		mockABI,
		common.FromHex(strings.TrimSpace(mockUSDCBin)),
		client,
		big.NewInt(1_000_000_000_000),
	)
	if err != nil {
		return fmt.Errorf("deploy MockUSDC: %w", err)
	}
	if _, err := waitForReceipt(ctx, client, mockTx.Hash()); err != nil {
		return err
	}

	routerAddress, routerTx, _, err := bind.DeployContract(
		newTransactor(ctx, key, chainID, gasPrice, nil),
		routerABI,
		common.FromHex(strings.TrimSpace(routerBin)),
		client,
		mockAddress,
	)
	if err != nil {
		return fmt.Errorf("deploy router: %w", err)
	}
	if _, err := waitForReceipt(ctx, client, routerTx.Hash()); err != nil {
		return err
	}

	mockContract := bind.NewBoundContract(mockAddress, mockABI, client, client, client)
	seedTokenTx, err := mockContract.Transact(
		newTransactor(ctx, key, chainID, gasPrice, nil),
		"transfer",
		routerAddress,
		big.NewInt(500_000_000_000),
	)
	if err != nil {
		return fmt.Errorf("seed MockUSDC: %w", err)
	}
	if _, err := waitForReceipt(ctx, client, seedTokenTx.Hash()); err != nil {
		return err
	}

	routerContract := bind.NewBoundContract(routerAddress, routerABI, client, client, client)
	seedKUDTx, err := routerContract.Transact(
		newTransactor(ctx, key, chainID, gasPrice, new(big.Int).Mul(big.NewInt(100), big.NewInt(1_000_000_000_000_000_000))),
		"seed",
	)
	if err != nil {
		return fmt.Errorf("seed KUD: %w", err)
	}
	if _, err := waitForReceipt(ctx, client, seedKUDTx.Hash()); err != nil {
		return err
	}

	reserve, err := tokenBalance(ctx, mockContract, routerAddress)
	if err != nil {
		return err
	}
	kudReserve, err := client.BalanceAt(ctx, routerAddress, nil)
	if err != nil {
		return err
	}
	return writeJSON(*resultFile, swapDeployment{
		MockUSDCAddress: mockAddress.Hex(), RouterAddress: routerAddress.Hex(),
		MockUSDCDeployTx: mockTx.Hash().Hex(), RouterDeployTx: routerTx.Hash().Hex(),
		TokenSeedTx: seedTokenTx.Hash().Hex(), KUDSeedTx: seedKUDTx.Hash().Hex(),
		TokenReserve: reserve.String(), KUDReserve: kudReserve.String(), LocalnetOnly: true,
	}, 0o644)
}

func runSwapSmoke(args []string) error {
	fs := flag.NewFlagSet("swap-smoke", flag.ContinueOnError)
	rpcURL := fs.String("rpc-url", "", "JSON-RPC endpoint")
	chainIDFlag := fs.Uint64("chain-id", 0, "expected EVM chain ID")
	senderKeyFile := fs.String("sender-key-file", "", "funded local account key")
	deploymentFile := fs.String("deployment-file", "", "swap deployment state")
	resultFile := fs.String("result-file", "", "swap result output")
	amountWei := fs.String("amount-wei", "1000000000000000000", "native KUD amount in akud")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *rpcURL == "" || *chainIDFlag == 0 || *senderKeyFile == "" || *deploymentFile == "" || *resultFile == "" {
		return errors.New("swap-smoke: all endpoint, key, deployment, and result flags are required")
	}
	var deployment swapDeployment
	if err := readJSON(*deploymentFile, &deployment); err != nil {
		return err
	}
	amount, err := decimalBigInt(*amountWei)
	if err != nil || amount.Sign() <= 0 {
		return errors.New("swap-smoke: amount must be positive")
	}

	client, ctx, cancel, err := dialClient(*rpcURL, receiptTimeout)
	if err != nil {
		return err
	}
	defer cancel()
	defer client.Close()
	chainID, err := ensureChainID(ctx, client, *chainIDFlag)
	if err != nil {
		return err
	}
	key, err := readKey(*senderKeyFile)
	if err != nil {
		return err
	}
	gasPrice, err := suggestedGasPrice(ctx, client)
	if err != nil {
		return err
	}
	mockABI, _ := abi.JSON(strings.NewReader(mockUSDCABIJSON))
	routerABI, _ := abi.JSON(strings.NewReader(routerABIJSON))
	mockAddress := common.HexToAddress(deployment.MockUSDCAddress)
	routerAddress := common.HexToAddress(deployment.RouterAddress)
	account := crypto.PubkeyToAddress(key.PublicKey)
	mockContract := bind.NewBoundContract(mockAddress, mockABI, client, client, client)
	routerContract := bind.NewBoundContract(routerAddress, routerABI, client, client, client)
	before, err := tokenBalance(ctx, mockContract, account)
	if err != nil {
		return err
	}
	tx, err := routerContract.Transact(
		newTransactor(ctx, key, chainID, gasPrice, amount),
		"swapExactKUDForUSDC",
		big.NewInt(0),
	)
	if err != nil {
		return err
	}
	receipt, err := waitForReceipt(ctx, client, tx.Hash())
	if err != nil {
		return err
	}
	if receipt.Status != 1 {
		return errors.New("swap transaction reverted")
	}
	after, err := tokenBalance(ctx, mockContract, account)
	if err != nil {
		return err
	}
	if after.Cmp(before) <= 0 {
		return errors.New("MockUSDC balance did not increase")
	}
	return writeJSON(*resultFile, swapResult{
		Account: account.Hex(), RouterAddress: routerAddress.Hex(), MockUSDCAddress: mockAddress.Hex(),
		KUDIn: amount.String(), MockUSDCBefore: before.String(), MockUSDCAfter: after.String(),
		TransactionHash: tx.Hash().Hex(), ReceiptStatus: statusHex(receipt.Status), GasUsed: receipt.GasUsed,
	}, 0o644)
}

func newTransactor(ctx context.Context, key *ecdsa.PrivateKey, chainID, gasPrice, value *big.Int) *bind.TransactOpts {
	auth, err := bind.NewKeyedTransactorWithChainID(key, chainID)
	if err != nil {
		panic(err)
	}
	auth.Context = ctx
	auth.GasPrice = gasPrice
	auth.GasLimit = 6_000_000
	auth.Value = value
	return auth
}

func tokenBalance(ctx context.Context, contract *bind.BoundContract, account common.Address) (*big.Int, error) {
	var values []interface{}
	if err := contract.Call(&bind.CallOpts{Context: ctx}, &values, "balanceOf", account); err != nil {
		return nil, err
	}
	if len(values) != 1 {
		return nil, fmt.Errorf("balanceOf returned %d values", len(values))
	}
	balance, ok := values[0].(*big.Int)
	if !ok {
		return nil, fmt.Errorf("unexpected balance type %T", values[0])
	}
	return balance, nil
}

func readJSON(path string, target any) error {
	bz, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(bz, target)
}
