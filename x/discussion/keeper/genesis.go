package keeper

import (
	"context"

	"cosmossdk.io/collections"

	"github.com/Kudora-Labs/kudora/x/discussion/types"
)

func (k Keeper) InitGenesis(ctx context.Context, gs types.GenesisState) error {
	if err := gs.Validate(); err != nil {
		return err
	}
	if err := k.Params.Set(ctx, gs.Params); err != nil {
		return err
	}
	if err := k.NextMessageID.Set(ctx, gs.NextMessageId); err != nil {
		return err
	}
	for _, message := range gs.Messages {
		if err := k.Messages.Set(ctx, messageKey(message.ProposalId, message.MessageId), types.StoredMessage{
			Author: message.Author, ParentId: message.ParentId, CreatedAt: message.CreatedAt, Content: message.Content,
		}); err != nil {
			return err
		}
	}
	for _, reaction := range gs.Reactions {
		if err := k.Reactions.Set(ctx, reactionKey(reaction.ProposalId, reaction.MessageId, reaction.Account), uint32(reaction.Reaction)); err != nil {
			return err
		}
	}
	for _, session := range gs.Sessions {
		if err := k.Sessions.Set(ctx, session.Session, types.StoredSession{Owner: session.Owner, ExpiresAt: session.ExpiresAt}); err != nil {
			return err
		}
	}
	return nil
}

func (k Keeper) ExportGenesis(ctx context.Context) (*types.GenesisState, error) {
	params, err := k.Params.Get(ctx)
	if err != nil {
		return nil, err
	}
	nextID, err := k.NextMessageID.Peek(ctx)
	if err != nil {
		return nil, err
	}
	gs := &types.GenesisState{Params: params, NextMessageId: nextID}
	if err := k.Messages.Walk(ctx, nil, func(key collections.Pair[uint64, uint64], stored types.StoredMessage) (bool, error) {
		gs.Messages = append(gs.Messages, messageView(key.K1(), key.K2(), stored))
		return false, nil
	}); err != nil {
		return nil, err
	}
	if err := k.Reactions.Walk(ctx, nil, func(key collections.Pair[collections.Pair[uint64, uint64], []byte], value uint32) (bool, error) {
		gs.Reactions = append(gs.Reactions, types.ReactionEntry{
			ProposalId: key.K1().K1(), MessageId: key.K1().K2(), Account: key.K2(), Reaction: types.Reaction(value),
		})
		return false, nil
	}); err != nil {
		return nil, err
	}
	if err := k.Sessions.Walk(ctx, nil, func(session []byte, stored types.StoredSession) (bool, error) {
		gs.Sessions = append(gs.Sessions, types.Session{Session: session, Owner: stored.Owner, ExpiresAt: stored.ExpiresAt})
		return false, nil
	}); err != nil {
		return nil, err
	}
	return gs, nil
}
