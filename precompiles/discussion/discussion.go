package discussion

import (
	"bytes"
	_ "embed"
	"fmt"
	"math/big"

	"cosmossdk.io/math"
	"github.com/cosmos/evm/precompiles/common"
	"github.com/ethereum/go-ethereum/accounts/abi"
	ethcommon "github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/vm"

	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/Kudora-Labs/kudora/x/discussion/keeper"
	"github.com/Kudora-Labs/kudora/x/discussion/types"
)

var (
	//go:embed abi.json
	abiJSON []byte
	ABI     abi.ABI
)

func init() {
	var err error
	ABI, err = abi.JSON(bytes.NewReader(abiJSON))
	if err != nil {
		panic(err)
	}
}

type Precompile struct {
	common.Precompile
	abi.ABI
	keeper keeper.Keeper
}

var _ vm.PrecompiledContract = Precompile{}

func NewPrecompile(k keeper.Keeper, bankKeeper common.BankKeeper) Precompile {
	return Precompile{
		Precompile: common.Precompile{
			KvGasConfig:           storetypes.KVGasConfig(),
			TransientKVGasConfig:  storetypes.TransientGasConfig(),
			ContractAddress:       ethcommon.HexToAddress(types.DiscussionPrecompileAddress),
			BalanceHandlerFactory: common.NewBalanceHandlerFactory(bankKeeper),
		},
		ABI:    ABI,
		keeper: k,
	}
}

func (Precompile) Name() string { return types.ModuleName }

func (p Precompile) RequiredGas(input []byte) uint64 {
	if len(input) < 4 {
		return 0
	}
	method, err := p.MethodById(input[:4])
	if err != nil {
		return 0
	}
	return p.Precompile.RequiredGas(input, p.isTransaction(method))
}

func (p Precompile) Run(evm *vm.EVM, contract *vm.Contract, readonly bool) ([]byte, error) {
	return p.RunNativeAction(evm, contract, func(ctx sdk.Context) ([]byte, error) {
		return p.execute(ctx, contract, readonly)
	})
}

func (p Precompile) execute(ctx sdk.Context, contract *vm.Contract, readonly bool) ([]byte, error) {
	method, args, err := common.SetupABI(p.ABI, contract, readonly, p.isTransaction)
	if err != nil {
		return nil, err
	}
	signer := sdk.AccAddress(contract.Caller().Bytes())

	switch method.Name {
	case "post":
		proposalID, parentID, content, err := postArgs(args)
		if err != nil {
			return nil, err
		}
		messageID, err := p.keeper.Post(ctx, signer, proposalID, parentID, content)
		if err != nil {
			return nil, err
		}
		return method.Outputs.Pack(messageID)
	case "react":
		proposalID, messageID, reaction, err := reactArgs(args)
		if err != nil {
			return nil, err
		}
		if err := p.keeper.React(ctx, signer, proposalID, messageID, types.Reaction(reaction)); err != nil {
			return nil, err
		}
		return method.Outputs.Pack(true)
	case "zap":
		proposalID, messageID, amount, err := valueArgs(args)
		if err != nil {
			return nil, err
		}
		if err := p.keeper.Zap(ctx, signer, proposalID, messageID, math.NewIntFromBigInt(amount)); err != nil {
			return nil, err
		}
		return method.Outputs.Pack(true)
	case "authorizeSession":
		session, expiresAt, fundAmount, err := sessionArgs(args)
		if err != nil {
			return nil, err
		}
		if err := p.keeper.AuthorizeSession(
			ctx,
			signer,
			sdk.AccAddress(session.Bytes()),
			int64(expiresAt),
			math.NewIntFromBigInt(fundAmount),
		); err != nil {
			return nil, err
		}
		return method.Outputs.Pack(true)
	case "revokeSession":
		session, err := addressArg(args)
		if err != nil {
			return nil, err
		}
		if err := p.keeper.RevokeSession(ctx, signer, sdk.AccAddress(session.Bytes())); err != nil {
			return nil, err
		}
		return method.Outputs.Pack(true)
	default:
		return nil, fmt.Errorf("unknown discussion method %q", method.Name)
	}
}

func (Precompile) isTransaction(*abi.Method) bool { return true }

func postArgs(args []interface{}) (uint64, uint64, []byte, error) {
	if len(args) != 3 {
		return 0, 0, nil, fmt.Errorf("expected 3 arguments")
	}
	proposalID, ok1 := args[0].(uint64)
	parentID, ok2 := args[1].(uint64)
	content, ok3 := args[2].([]byte)
	if !ok1 || !ok2 || !ok3 {
		return 0, 0, nil, fmt.Errorf("invalid post arguments")
	}
	return proposalID, parentID, content, nil
}

func reactArgs(args []interface{}) (uint64, uint64, uint8, error) {
	if len(args) != 3 {
		return 0, 0, 0, fmt.Errorf("expected 3 arguments")
	}
	proposalID, ok1 := args[0].(uint64)
	messageID, ok2 := args[1].(uint64)
	reaction, ok3 := args[2].(uint8)
	if !ok1 || !ok2 || !ok3 {
		return 0, 0, 0, fmt.Errorf("invalid react arguments")
	}
	return proposalID, messageID, reaction, nil
}

func valueArgs(args []interface{}) (uint64, uint64, *big.Int, error) {
	if len(args) != 3 {
		return 0, 0, nil, fmt.Errorf("expected 3 arguments")
	}
	proposalID, ok1 := args[0].(uint64)
	messageID, ok2 := args[1].(uint64)
	amount, ok3 := args[2].(*big.Int)
	if !ok1 || !ok2 || !ok3 || amount.Sign() <= 0 {
		return 0, 0, nil, fmt.Errorf("invalid value arguments")
	}
	return proposalID, messageID, amount, nil
}

func sessionArgs(args []interface{}) (ethcommon.Address, uint64, *big.Int, error) {
	if len(args) != 3 {
		return ethcommon.Address{}, 0, nil, fmt.Errorf("expected 3 arguments")
	}
	session, ok1 := args[0].(ethcommon.Address)
	expiresAt, ok2 := args[1].(uint64)
	amount, ok3 := args[2].(*big.Int)
	if !ok1 || !ok2 || !ok3 || session == (ethcommon.Address{}) || expiresAt > uint64(^uint64(0)>>1) || amount.Sign() <= 0 {
		return ethcommon.Address{}, 0, nil, fmt.Errorf("invalid session arguments")
	}
	return session, expiresAt, amount, nil
}

func addressArg(args []interface{}) (ethcommon.Address, error) {
	if len(args) != 1 {
		return ethcommon.Address{}, fmt.Errorf("expected one argument")
	}
	address, ok := args[0].(ethcommon.Address)
	if !ok || address == (ethcommon.Address{}) {
		return ethcommon.Address{}, fmt.Errorf("invalid session address")
	}
	return address, nil
}
