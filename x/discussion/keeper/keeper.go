package keeper

import (
	"context"
	"fmt"

	"cosmossdk.io/collections"
	"cosmossdk.io/core/address"
	corestore "cosmossdk.io/core/store"
	"github.com/cosmos/cosmos-sdk/codec"

	"github.com/Kudora-Labs/kudora/x/discussion/types"
)

type ProposalExists func(ctx context.Context, proposalID uint64) (bool, error)

type Keeper struct {
	storeService   corestore.KVStoreService
	cargoCodec     codec.Codec
	addressCodec   address.Codec
	authority      []byte
	bankKeeper     types.BankKeeper
	proposalExists ProposalExists

	Schema        collections.Schema
	Params        collections.Item[types.Params]
	NextMessageID collections.Sequence
	Messages      collections.Map[collections.Pair[uint64, uint64], types.StoredMessage]
	Reactions     collections.Map[collections.Pair[collections.Pair[uint64, uint64], []byte], uint32]
	Sessions      collections.Map[[]byte, types.StoredSession]
}

func NewKeeper(
	storeService corestore.KVStoreService,
	cargoCodec codec.Codec,
	addressCodec address.Codec,
	authority []byte,
	bankKeeper types.BankKeeper,
	proposalExists ProposalExists,
) Keeper {
	if _, err := addressCodec.BytesToString(authority); err != nil {
		panic(fmt.Sprintf("invalid discussion authority: %s", err))
	}

	sb := collections.NewSchemaBuilder(storeService)
	k := Keeper{
		storeService:   storeService,
		cargoCodec:     cargoCodec,
		addressCodec:   addressCodec,
		authority:      authority,
		bankKeeper:     bankKeeper,
		proposalExists: proposalExists,
		Params:         collections.NewItem(sb, types.ParamsKey, "params", codec.CollValue[types.Params](cargoCodec)),
		NextMessageID:  collections.NewSequence(sb, types.NextMessageIDKey, "next_message_id"),
		Messages: collections.NewMap(
			sb,
			types.MessageKey,
			"messages",
			collections.PairKeyCodec(collections.Uint64Key, collections.Uint64Key),
			codec.CollValue[types.StoredMessage](cargoCodec),
		),
		Reactions: collections.NewMap(
			sb,
			types.ReactionKey,
			"reactions",
			collections.PairKeyCodec(
				collections.PairKeyCodec(collections.Uint64Key, collections.Uint64Key),
				collections.BytesKey,
			),
			collections.Uint32Value,
		),
		Sessions: collections.NewMap(
			sb,
			types.SessionKey,
			"sessions",
			collections.BytesKey,
			codec.CollValue[types.StoredSession](cargoCodec),
		),
	}

	schema, err := sb.Build()
	if err != nil {
		panic(err)
	}
	k.Schema = schema
	return k
}

func (k Keeper) Authority() []byte {
	return k.authority
}
