package app

import (
	"encoding/json"
	"sort"

	sdkmath "cosmossdk.io/math"
	wasmtypes "github.com/CosmWasm/wasmd/x/wasm/types"
	precompiletypes "github.com/cosmos/evm/precompiles/types"
	erc20types "github.com/cosmos/evm/x/erc20/types"
	feemarkettypes "github.com/cosmos/evm/x/feemarket/types"
	evmtypes "github.com/cosmos/evm/x/vm/types"
	"github.com/ethereum/go-ethereum/common"
	corevm "github.com/ethereum/go-ethereum/core/vm"

	"github.com/cosmos/cosmos-sdk/codec"
	bankkeeper "github.com/cosmos/cosmos-sdk/x/bank/keeper"
	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	govkeeper "github.com/cosmos/cosmos-sdk/x/gov/keeper"
	minttypes "github.com/cosmos/cosmos-sdk/x/mint/types"
	stakingkeeper "github.com/cosmos/cosmos-sdk/x/staking/keeper"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"

	discussionprecompile "github.com/Kudora-Labs/kudora/precompiles/discussion"
	discussionkeeper "github.com/Kudora-Labs/kudora/x/discussion/keeper"
	discussiontypes "github.com/Kudora-Labs/kudora/x/discussion/types"
)

const (
	DefaultBaseDenom    = "akud"
	DefaultDisplayDenom = "KUD"
	DefaultDenomName    = "Kudora"
	DefaultDenomSymbol  = "KUD"

	DefaultDenomDecimals  uint32 = 18
	DefaultChainID               = "kudora_12000-1"
	DefaultEVMChainID     uint64 = 120001
	ExpectedEthChainIDHex        = "0x1d4c1"
)

// GenesisState of the blockchain is represented here as a map of raw json
// messages keyed by module name.
type GenesisState map[string]json.RawMessage

// DefaultGenesis returns the default genesis for Kudora.
func (app *App) DefaultGenesis() map[string]json.RawMessage {
	genesis := app.BasicModuleManager.DefaultGenesis(app.appCodec)

	mintGenesis := minttypes.DefaultGenesisState()
	mintGenesis.Params.MintDenom = DefaultBaseDenom
	genesis[minttypes.ModuleName] = app.appCodec.MustMarshalJSON(mintGenesis)

	stakingGenesis := stakingtypes.DefaultGenesisState()
	stakingGenesis.Params.BondDenom = DefaultBaseDenom
	genesis[stakingtypes.ModuleName] = app.appCodec.MustMarshalJSON(stakingGenesis)

	bankGenesis := banktypes.DefaultGenesisState()
	bankGenesis.DenomMetadata = []banktypes.Metadata{kudoraBankMetadata()}
	genesis[banktypes.ModuleName] = app.appCodec.MustMarshalJSON(bankGenesis)

	evmGenesis := NewEVMGenesisState()
	genesis[evmtypes.ModuleName] = app.appCodec.MustMarshalJSON(evmGenesis)

	erc20Genesis := erc20types.DefaultGenesisState()
	genesis[erc20types.ModuleName] = app.appCodec.MustMarshalJSON(erc20Genesis)

	feeMarketGenesis := NewFeeMarketGenesisState()
	genesis[feemarkettypes.ModuleName] = app.appCodec.MustMarshalJSON(feeMarketGenesis)

	wasmGenesis := NewWasmGenesisState()
	genesis[wasmtypes.ModuleName] = app.appCodec.MustMarshalJSON(wasmGenesis)

	return genesis
}

func NewEVMGenesisState() *evmtypes.GenesisState {
	evmGenesis := evmtypes.DefaultGenesisState()
	evmGenesis.Params.EvmDenom = DefaultBaseDenom
	evmGenesis.Params.ActiveStaticPrecompiles = kudoraActiveStaticPrecompiles()
	evmGenesis.Preinstalls = []evmtypes.Preinstall{}
	return evmGenesis
}

func NewFeeMarketGenesisState() *feemarkettypes.GenesisState {
	feeMarketGenesis := feemarkettypes.DefaultGenesisState()
	feeMarketGenesis.Params = feemarkettypes.NewParams(
		false,
		8,
		2,
		sdkmath.LegacyNewDec(100_000_000),
		0,
		sdkmath.LegacyNewDec(100_000_000),
		sdkmath.LegacyNewDecWithPrec(5, 1),
	)
	return feeMarketGenesis
}

func NewWasmGenesisState() *wasmtypes.GenesisState {
	params := wasmtypes.DefaultParams()
	params.CodeUploadAccess = wasmtypes.AllowNobody
	params.InstantiateDefaultPermission = wasmtypes.AccessTypeNobody

	return &wasmtypes.GenesisState{
		Params: params,
	}
}

func kudoraBankMetadata() banktypes.Metadata {
	return banktypes.Metadata{
		Description: "Native staking and gas token for Kudora.",
		Base:        DefaultBaseDenom,
		Display:     DefaultDisplayDenom,
		Name:        DefaultDenomName,
		Symbol:      DefaultDenomSymbol,
		DenomUnits: []*banktypes.DenomUnit{
			{
				Denom:    DefaultBaseDenom,
				Exponent: 0,
			},
			{
				Denom:    DefaultDisplayDenom,
				Exponent: DefaultDenomDecimals,
			},
		},
	}
}

func kudoraBaseStaticPrecompiles() precompiletypes.StaticPrecompiles {
	return precompiletypes.NewStaticPrecompiles().
		WithPraguePrecompiles().
		WithP256Precompile().
		WithBech32Precompile()
}

func kudoraStaticPrecompiles(
	govKeeper govkeeper.Keeper,
	stakingKeeper stakingkeeper.Keeper,
	bankKeeper bankkeeper.Keeper,
	cargoCodec codec.Codec,
	discussionKeeper discussionkeeper.Keeper,
) precompiletypes.StaticPrecompiles {
	precompiles := kudoraBaseStaticPrecompiles().
		WithStakingPrecompile(stakingKeeper, bankKeeper).
		WithGovPrecompile(govKeeper, bankKeeper, cargoCodec)
	discussion := discussionprecompile.NewPrecompile(discussionKeeper, bankKeeper)
	precompiles[discussion.Address()] = discussion
	return precompiles
}

func kudoraActiveStaticPrecompiles() []string {
	precompiles := kudoraBaseStaticPrecompiles()
	precompiles[common.HexToAddress(evmtypes.StakingPrecompileAddress)] = nil
	precompiles[common.HexToAddress(evmtypes.GovPrecompileAddress)] = nil
	precompiles[common.HexToAddress(discussiontypes.DiscussionPrecompileAddress)] = nil
	prague := make(map[string]struct{}, len(corevm.PrecompiledAddressesPrague))
	for _, addr := range corevm.PrecompiledAddressesPrague {
		prague[addr.Hex()] = struct{}{}
	}

	active := make([]string, 0, len(precompiles))
	for addr := range precompiles {
		if _, ok := prague[addr.Hex()]; ok {
			continue
		}
		active = append(active, addr.Hex())
	}

	sort.Strings(active)
	return active
}
