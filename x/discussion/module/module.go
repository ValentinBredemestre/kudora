package discussion

import (
	"encoding/json"
	"fmt"

	"cosmossdk.io/core/appmodule"
	"github.com/cosmos/cosmos-sdk/client"
	"github.com/cosmos/cosmos-sdk/codec"
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/module"
	"github.com/grpc-ecosystem/grpc-gateway/runtime"
	"google.golang.org/grpc"

	"github.com/Kudora-Labs/kudora/x/discussion/keeper"
	"github.com/Kudora-Labs/kudora/x/discussion/types"
)

var (
	_ module.AppModuleBasic = AppModule{}
	_ module.AppModule      = AppModule{}
	_ module.HasGenesis     = AppModule{}
	_ appmodule.AppModule   = AppModule{}
)

type AppModule struct {
	cdc    codec.Codec
	keeper keeper.Keeper
}

func NewAppModule(cdc codec.Codec, keeper keeper.Keeper) AppModule {
	return AppModule{cdc: cdc, keeper: keeper}
}

func (AppModule) IsAppModule()                                {}
func (AppModule) IsOnePerModuleType()                         {}
func (AppModule) Name() string                                { return types.ModuleName }
func (AppModule) RegisterLegacyAminoCodec(*codec.LegacyAmino) {}

func (AppModule) RegisterInterfaces(registrar codectypes.InterfaceRegistry) {
	types.RegisterInterfaces(registrar)
}

func (AppModule) RegisterGRPCGatewayRoutes(clientCtx client.Context, mux *runtime.ServeMux) {
	if err := types.RegisterQueryHandlerClient(clientCtx.CmdContext, mux, types.NewQueryClient(clientCtx)); err != nil {
		panic(err)
	}
}

func (am AppModule) RegisterServices(registrar grpc.ServiceRegistrar) error {
	types.RegisterMsgServer(registrar, keeper.NewMsgServerImpl(am.keeper))
	types.RegisterQueryServer(registrar, keeper.NewQueryServerImpl(am.keeper))
	return nil
}

func (am AppModule) DefaultGenesis(codec.JSONCodec) json.RawMessage {
	return am.cdc.MustMarshalJSON(types.DefaultGenesis())
}

func (am AppModule) ValidateGenesis(_ codec.JSONCodec, _ client.TxEncodingConfig, raw json.RawMessage) error {
	var state types.GenesisState
	if err := am.cdc.UnmarshalJSON(raw, &state); err != nil {
		return fmt.Errorf("failed to unmarshal %s genesis: %w", types.ModuleName, err)
	}
	return state.Validate()
}

func (am AppModule) InitGenesis(ctx sdk.Context, _ codec.JSONCodec, raw json.RawMessage) {
	var state types.GenesisState
	if err := am.cdc.UnmarshalJSON(raw, &state); err != nil {
		panic(err)
	}
	if err := am.keeper.InitGenesis(ctx, state); err != nil {
		panic(err)
	}
}

func (am AppModule) ExportGenesis(ctx sdk.Context, _ codec.JSONCodec) json.RawMessage {
	state, err := am.keeper.ExportGenesis(ctx)
	if err != nil {
		panic(err)
	}
	return am.cdc.MustMarshalJSON(state)
}

func (AppModule) ConsensusVersion() uint64 { return 1 }
