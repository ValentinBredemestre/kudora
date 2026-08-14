package cmd

import (
	"errors"
	"io"

	"github.com/CosmWasm/wasmd/x/wasm"
	wasmcli "github.com/CosmWasm/wasmd/x/wasm/client/cli"
	gogoproto "github.com/cosmos/gogoproto/proto"
	"github.com/spf13/cast"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"google.golang.org/grpc"
	"google.golang.org/protobuf/reflect/protoregistry"

	autocliv1 "cosmossdk.io/api/cosmos/autocli/v1"
	"cosmossdk.io/client/v2/autocli"
	autocliflag "cosmossdk.io/client/v2/autocli/flag"
	cmtcli "github.com/cometbft/cometbft/libs/cli"

	dbm "github.com/cosmos/cosmos-db"
	cosmosevmcmd "github.com/cosmos/evm/client"
	evmdebug "github.com/cosmos/evm/client/debug"
	cosmosevmserver "github.com/cosmos/evm/server"
	srvflags "github.com/cosmos/evm/server/flags"
	"github.com/cosmos/evm/utils"

	"cosmossdk.io/log/v2"
	confixcmd "cosmossdk.io/tools/confix/cmd"
	"github.com/cosmos/cosmos-sdk/store/v2"
	snapshottypes "github.com/cosmos/cosmos-sdk/store/v2/snapshots/types"
	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"

	"github.com/cosmos/cosmos-sdk/baseapp"
	"github.com/cosmos/cosmos-sdk/client"
	"github.com/cosmos/cosmos-sdk/client/flags"
	"github.com/cosmos/cosmos-sdk/client/pruning"
	"github.com/cosmos/cosmos-sdk/client/rpc"
	"github.com/cosmos/cosmos-sdk/client/snapshot"
	sdkserver "github.com/cosmos/cosmos-sdk/server"
	servertypes "github.com/cosmos/cosmos-sdk/server/types"
	authcmd "github.com/cosmos/cosmos-sdk/x/auth/client/cli"
	bank "github.com/cosmos/cosmos-sdk/x/bank"
	bankcli "github.com/cosmos/cosmos-sdk/x/bank/client/cli"
	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	genutilcli "github.com/cosmos/cosmos-sdk/x/genutil/client/cli"
	gov "github.com/cosmos/cosmos-sdk/x/gov"
	govtypes "github.com/cosmos/cosmos-sdk/x/gov/types"
	staking "github.com/cosmos/cosmos-sdk/x/staking"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"

	"github.com/Kudora-Labs/kudora/app"
	integritycli "github.com/Kudora-Labs/kudora/x/integrity/client/cli"
)

func initRootCmd(rootCmd *cobra.Command, tempApp *app.App) {
	sdkAppCreator := func(logger log.Logger, db dbm.DB, appOpts servertypes.AppOptions) servertypes.Application {
		return newApp(logger, db, nil, appOpts)
	}

	rootCmd.AddCommand(
		NewInitCmd(tempApp, tempApp.BasicModuleManager),
		NewInPlaceTestnetCmd(),
		NewTestnetMultiNodeCmd(tempApp.BasicModuleManager, banktypes.GenesisBalancesIterator{}),
		genutilcli.Commands(tempApp.TxConfig(), tempApp.BasicModuleManager, app.DefaultNodeHome),
		cmtcli.NewCompletionCmd(rootCmd, true),
		evmdebug.Cmd(),
		confixcmd.ConfigCommand(),
		pruning.Cmd(sdkAppCreator, app.DefaultNodeHome),
		snapshot.Cmd(sdkAppCreator),
	)

	cosmosevmserver.AddCommands(
		rootCmd,
		cosmosevmserver.NewDefaultStartOptions(newEVMApp, app.DefaultNodeHome),
		appExport,
		addModuleInitFlags,
	)
	wasmcli.ExtendUnsafeResetAllCmd(rootCmd)

	rootCmd.AddCommand(
		cosmosevmcmd.KeyCommands(app.DefaultNodeHome, true),
		sdkserver.StatusCommand(),
		queryCommand(tempApp),
		txCommand(tempApp),
	)

	if _, err := srvflags.AddTxFlags(rootCmd); err != nil {
		panic(err)
	}
}

func addModuleInitFlags(startCmd *cobra.Command) {
	wasm.AddModuleInitFlags(startCmd)
}

func autoCLIBuilder(tempApp *app.App) (*autocli.Builder, error) {
	var (
		mergedFiles autocliflag.FileResolver
		err         error
	)

	mergedFiles, err = gogoproto.MergedRegistry()
	if err != nil {
		mergedFiles = tempApp.InterfaceRegistry()
	}

	builder := &autocli.Builder{
		Builder: autocliflag.Builder{
			TypeResolver:          protoregistry.GlobalTypes,
			FileResolver:          mergedFiles,
			AddressCodec:          tempApp.AccountKeeper.AddressCodec(),
			ValidatorAddressCodec: tempApp.StakingKeeper.ValidatorAddressCodec(),
			ConsensusAddressCodec: tempApp.StakingKeeper.ConsensusAddressCodec(),
		},
		GetClientConn: func(cmd *cobra.Command) (grpc.ClientConnInterface, error) {
			clientCtx, err := client.GetClientQueryContext(cmd)
			if err != nil {
				return nil, err
			}
			return clientCtx, nil
		},
		AddQueryConnFlags: func(c *cobra.Command) {
			flags.AddQueryFlagsToCmd(c)
			flags.AddKeyringFlags(c.Flags())
		},
		AddTxConnFlags: flags.AddTxFlagsToCmd,
	}

	return builder, builder.ValidateAndComplete()
}

func addAutoCLIQueryModule(parent *cobra.Command, moduleName string, descriptor *autocliv1.ServiceCommandDescriptor, builder *autocli.Builder) error {
	if descriptor == nil {
		return nil
	}

	short := descriptor.Short
	if short == "" {
		short = "Querying commands for the " + moduleName + " module"
	}

	moduleCmd := &cobra.Command{
		Use:                        moduleName,
		Short:                      short,
		DisableFlagParsing:         false,
		SuggestionsMinimumDistance: 2,
		RunE:                       client.ValidateCmd,
	}

	if err := builder.AddQueryServiceCommands(moduleCmd, descriptor); err != nil {
		return err
	}

	parent.AddCommand(moduleCmd)
	return nil
}

func queryCommand(tempApp *app.App) *cobra.Command {
	cmd := &cobra.Command{
		Use:                        "query",
		Aliases:                    []string{"q"},
		Short:                      "Querying subcommands",
		DisableFlagParsing:         false,
		SuggestionsMinimumDistance: 2,
		RunE:                       client.ValidateCmd,
	}

	cmd.AddCommand(
		rpc.QueryEventForTxCmd(),
		rpc.ValidatorCommand(),
		authcmd.QueryTxsByEventsCmd(),
		authcmd.QueryTxCmd(),
		sdkserver.QueryBlockCmd(),
		sdkserver.QueryBlockResultsCmd(),
	)
	cmd.AddCommand(wasm.AppModuleBasic{}.GetQueryCmd())
	cmd.AddCommand(integritycli.GetQueryCmd())

	builder, err := autoCLIBuilder(tempApp)
	if err != nil {
		panic(err)
	}

	if err := addAutoCLIQueryModule(cmd, banktypes.ModuleName, bank.AppModule{}.AutoCLIOptions().Query, builder); err != nil {
		panic(err)
	}
	if err := addAutoCLIQueryModule(cmd, govtypes.ModuleName, gov.AppModule{}.AutoCLIOptions().Query, builder); err != nil {
		panic(err)
	}
	if err := addAutoCLIQueryModule(cmd, stakingtypes.ModuleName, staking.AppModule{}.AutoCLIOptions().Query, builder); err != nil {
		panic(err)
	}

	cmd.PersistentFlags().String(flags.FlagChainID, "", "The network chain ID")
	return cmd
}

func txCommand(tempApp *app.App) *cobra.Command {
	cmd := &cobra.Command{
		Use:                        "tx",
		Short:                      "Transactions subcommands",
		DisableFlagParsing:         false,
		SuggestionsMinimumDistance: 2,
		RunE:                       client.ValidateCmd,
	}

	cmd.AddCommand(
		authcmd.GetSignCommand(),
		authcmd.GetSignBatchCommand(),
		authcmd.GetMultiSignCommand(),
		authcmd.GetMultiSignBatchCmd(),
		authcmd.GetValidateSignaturesCommand(),
		authcmd.GetBroadcastCommand(),
		authcmd.GetEncodeCommand(),
		authcmd.GetDecodeCommand(),
		authcmd.GetSimulateCmd(),
	)
	cmd.AddCommand(bankcli.NewTxCmd(tempApp.AccountKeeper.AddressCodec()))
	cmd.AddCommand(gov.NewAppModuleBasic(nil).GetTxCmd())
	cmd.AddCommand(wasm.AppModuleBasic{}.GetTxCmd())
	cmd.AddCommand(integritycli.GetTxCmd())

	builder, err := autoCLIBuilder(tempApp)
	if err != nil {
		panic(err)
	}
	if err := addAutoCLITxModule(cmd, stakingtypes.ModuleName, staking.AppModule{}.AutoCLIOptions().Tx, builder); err != nil {
		panic(err)
	}

	cmd.PersistentFlags().String(flags.FlagChainID, "", "The network chain ID")
	return cmd
}

func addAutoCLITxModule(parent *cobra.Command, moduleName string, descriptor *autocliv1.ServiceCommandDescriptor, builder *autocli.Builder) error {
	if descriptor == nil {
		return nil
	}

	short := descriptor.Short
	if short == "" {
		short = "Transaction commands for the " + moduleName + " module"
	}

	moduleCmd := &cobra.Command{
		Use:                        moduleName,
		Short:                      short,
		DisableFlagParsing:         false,
		SuggestionsMinimumDistance: 2,
		RunE:                       client.ValidateCmd,
	}

	if err := builder.AddMsgServiceCommands(moduleCmd, descriptor); err != nil {
		return err
	}

	parent.AddCommand(moduleCmd)
	return nil
}

func newApp(
	logger log.Logger,
	db dbm.DB,
	traceStore io.Writer,
	appOpts servertypes.AppOptions,
) servertypes.Application {
	chainID, err := getChainIDFromOpts(appOpts)
	if err != nil {
		panic(err)
	}

	baseAppOptions := newBaseAppOptions(appOpts, chainID)
	return app.New(logger, db, traceStore, true, appOpts, baseAppOptions...)
}

func newEVMApp(
	logger log.Logger,
	db dbm.DB,
	appOpts servertypes.AppOptions,
) cosmosevmserver.Application {
	created := newApp(logger, db, nil, appOpts)
	evmApp, ok := created.(*app.App)
	if !ok {
		panic("newApp did not return *app.App")
	}
	return evmApp
}

func newBaseAppOptions(appOpts servertypes.AppOptions, chainID string) []func(*baseapp.BaseApp) {
	var cache storetypes.MultiStorePersistentCache
	if cast.ToBool(appOpts.Get(sdkserver.FlagInterBlockCache)) {
		cache = store.NewCommitKVStoreCacheManager()
	}

	pruningOpts, err := sdkserver.GetPruningOptionsFromFlags(appOpts)
	if err != nil {
		panic(err)
	}

	snapshotStore, err := sdkserver.GetSnapshotStore(appOpts)
	if err != nil {
		panic(err)
	}

	snapshotOptions := snapshottypes.NewSnapshotOptions(
		cast.ToUint64(appOpts.Get(sdkserver.FlagStateSyncSnapshotInterval)),
		cast.ToUint32(appOpts.Get(sdkserver.FlagStateSyncSnapshotKeepRecent)),
	)

	return []func(*baseapp.BaseApp){
		baseapp.SetPruning(pruningOpts),
		baseapp.SetMinGasPrices(cast.ToString(appOpts.Get(sdkserver.FlagMinGasPrices))),
		baseapp.SetQueryGasLimit(cast.ToUint64(appOpts.Get(sdkserver.FlagQueryGasLimit))),
		baseapp.SetHaltHeight(cast.ToUint64(appOpts.Get(sdkserver.FlagHaltHeight))),
		baseapp.SetHaltTime(cast.ToUint64(appOpts.Get(sdkserver.FlagHaltTime))),
		baseapp.SetMinRetainBlocks(cast.ToUint64(appOpts.Get(sdkserver.FlagMinRetainBlocks))),
		baseapp.SetInterBlockCache(cache),
		baseapp.SetTrace(cast.ToBool(appOpts.Get(sdkserver.FlagTrace))),
		baseapp.SetIndexEvents(cast.ToStringSlice(appOpts.Get(sdkserver.FlagIndexEvents))),
		baseapp.SetSnapshot(snapshotStore, snapshotOptions),
		baseapp.SetIAVLCacheSize(cast.ToInt(appOpts.Get(sdkserver.FlagIAVLCacheSize))),
		baseapp.SetIAVLDisableFastNode(cast.ToBool(appOpts.Get(sdkserver.FlagDisableIAVLFastNode))),
		baseapp.SetChainID(chainID),
	}
}

func appExport(
	logger log.Logger,
	db dbm.DB,
	height int64,
	forZeroHeight bool,
	jailAllowedAddrs []string,
	appOpts servertypes.AppOptions,
	modulesToExport []string,
) (servertypes.ExportedApp, error) {
	homePath, ok := appOpts.Get(flags.FlagHome).(string)
	if !ok || homePath == "" {
		return servertypes.ExportedApp{}, errors.New("application home not set")
	}

	viperAppOpts, ok := appOpts.(*viper.Viper)
	if !ok {
		return servertypes.ExportedApp{}, errors.New("appOpts is not viper.Viper")
	}

	viperAppOpts.Set(sdkserver.FlagInvCheckPeriod, 1)
	appOpts = viperAppOpts

	chainID, err := getChainIDFromOpts(appOpts)
	if err != nil {
		return servertypes.ExportedApp{}, err
	}

	baseAppOptions := newBaseAppOptions(appOpts, chainID)

	var kudoraApp *app.App
	if height != -1 {
		kudoraApp = app.New(logger, db, nil, false, appOpts, baseAppOptions...)
		if err := kudoraApp.LoadHeight(height); err != nil {
			return servertypes.ExportedApp{}, err
		}
	} else {
		kudoraApp = app.New(logger, db, nil, true, appOpts, baseAppOptions...)
	}

	return kudoraApp.ExportAppStateAndValidators(forZeroHeight, jailAllowedAddrs, modulesToExport)
}

func getChainIDFromOpts(appOpts servertypes.AppOptions) (string, error) {
	chainID := cast.ToString(appOpts.Get(flags.FlagChainID))
	if chainID != "" {
		return chainID, nil
	}

	homeDir := cast.ToString(appOpts.Get(flags.FlagHome))
	if homeDir == "" {
		homeDir = app.DefaultNodeHome
	}

	return utils.GetChainIDFromHome(homeDir)
}
