package keeper

import (
	"bytes"
	"context"
	"errors"
	"strconv"

	"cosmossdk.io/collections"
	sdkmath "cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"

	"github.com/Kudora-Labs/kudora/x/discussion/types"
)

func messageKey(proposalID, messageID uint64) collections.Pair[uint64, uint64] {
	return collections.Join(proposalID, messageID)
}

func reactionKey(proposalID, messageID uint64, account []byte) collections.Pair[collections.Pair[uint64, uint64], []byte] {
	return collections.Join(messageKey(proposalID, messageID), account)
}

func (k Keeper) GetMessage(ctx context.Context, proposalID, messageID uint64) (types.StoredMessage, error) {
	message, err := k.Messages.Get(ctx, messageKey(proposalID, messageID))
	if errors.Is(err, collections.ErrNotFound) {
		return types.StoredMessage{}, types.ErrMessageNotFound
	}
	return message, err
}

func (k Keeper) GetSession(ctx context.Context, session []byte) (types.StoredSession, error) {
	stored, err := k.Sessions.Get(ctx, session)
	if errors.Is(err, collections.ErrNotFound) {
		return types.StoredSession{}, types.ErrInvalidSession.Wrap("session is not authorized")
	}
	if err == nil && sdk.UnwrapSDKContext(ctx).BlockTime().Unix() >= stored.ExpiresAt {
		return types.StoredSession{}, types.ErrSessionExpired
	}
	return stored, err
}

func (k Keeper) Post(
	ctx context.Context,
	signer sdk.AccAddress,
	proposalID,
	parentID uint64,
	content []byte,
) (uint64, error) {
	if err := types.ValidateContent(content); err != nil {
		return 0, err
	}
	if proposalID > 0 {
		exists, err := k.proposalExists(ctx, proposalID)
		if err != nil {
			return 0, err
		}
		if !exists {
			return 0, types.ErrProposalMissing.Wrapf("proposal %d", proposalID)
		}
	}
	if parentID > 0 {
		if _, err := k.GetMessage(ctx, proposalID, parentID); err != nil {
			return 0, types.ErrParentNotFound.Wrapf("message %d", parentID)
		}
	}

	author, err := k.resolveAuthor(ctx, signer)
	if err != nil {
		return 0, err
	}
	params, err := k.Params.Get(ctx)
	if err != nil {
		return 0, err
	}
	if err := k.bankKeeper.SendCoinsFromAccountToModule(
		ctx,
		signer,
		authtypes.FeeCollectorName,
		sdk.NewCoins(params.PostFee),
	); err != nil {
		return 0, err
	}

	messageID, err := k.NextMessageID.Next(ctx)
	if err != nil {
		return 0, err
	}
	sdkCtx := sdk.UnwrapSDKContext(ctx)
	stored := types.StoredMessage{
		Author:    append([]byte(nil), author...),
		ParentId:  parentID,
		CreatedAt: sdkCtx.BlockTime().Unix(),
		Content:   append([]byte(nil), content...),
	}
	if err := k.Messages.Set(ctx, messageKey(proposalID, messageID), stored); err != nil {
		return 0, err
	}
	sdkCtx.EventManager().EmitEvent(sdk.NewEvent(
		"discussion_post",
		sdk.NewAttribute("proposal_id", strconv.FormatUint(proposalID, 10)),
		sdk.NewAttribute("message_id", strconv.FormatUint(messageID, 10)),
	))
	return messageID, nil
}

func (k Keeper) React(
	ctx context.Context,
	signer sdk.AccAddress,
	proposalID,
	messageID uint64,
	reaction types.Reaction,
) error {
	if _, err := k.GetMessage(ctx, proposalID, messageID); err != nil {
		return err
	}
	author, err := k.resolveAuthor(ctx, signer)
	if err != nil {
		return err
	}
	key := reactionKey(proposalID, messageID, author)
	switch reaction {
	case types.Reaction_REACTION_UNSPECIFIED:
		err := k.Reactions.Remove(ctx, key)
		if errors.Is(err, collections.ErrNotFound) {
			return nil
		}
		return err
	case types.Reaction_REACTION_USEFUL, types.Reaction_REACTION_NOT_USEFUL:
		return k.Reactions.Set(ctx, key, uint32(reaction))
	default:
		return types.ErrInvalidReaction
	}
}

func (k Keeper) Zap(
	ctx context.Context,
	signer sdk.AccAddress,
	proposalID,
	messageID uint64,
	amount sdkmath.Int,
) error {
	if !amount.IsPositive() {
		return types.ErrInvalidAmount
	}
	if isSession, err := k.Sessions.Has(ctx, signer); err != nil {
		return err
	} else if isSession {
		return types.ErrSessionForbidden
	}
	message, err := k.GetMessage(ctx, proposalID, messageID)
	if err != nil {
		return err
	}
	return k.bankKeeper.SendCoins(
		ctx,
		signer,
		sdk.AccAddress(message.Author),
		sdk.NewCoins(sdk.NewCoin(types.NativeDenom, amount)),
	)
}

func (k Keeper) AuthorizeSession(
	ctx context.Context,
	owner,
	session sdk.AccAddress,
	expiresAt int64,
	fundAmount sdkmath.Int,
) error {
	if bytes.Equal(owner, session) || expiresAt <= sdk.UnwrapSDKContext(ctx).BlockTime().Unix() {
		return types.ErrInvalidSession.Wrap("session address and future expiry are required")
	}
	if !fundAmount.IsPositive() {
		return types.ErrInvalidAmount
	}
	if isSession, err := k.Sessions.Has(ctx, owner); err != nil {
		return err
	} else if isSession {
		return types.ErrSessionForbidden
	}
	if current, err := k.Sessions.Get(ctx, session); err == nil && !bytes.Equal(current.Owner, owner) {
		return types.ErrUnauthorized.Wrap("session belongs to another owner")
	} else if err != nil && !errors.Is(err, collections.ErrNotFound) {
		return err
	}
	if err := k.bankKeeper.SendCoins(
		ctx,
		owner,
		session,
		sdk.NewCoins(sdk.NewCoin(types.NativeDenom, fundAmount)),
	); err != nil {
		return err
	}
	return k.Sessions.Set(ctx, session, types.StoredSession{
		Owner:     append([]byte(nil), owner...),
		ExpiresAt: expiresAt,
	})
}

func (k Keeper) RevokeSession(ctx context.Context, owner, session sdk.AccAddress) error {
	stored, err := k.GetSession(ctx, session)
	if err != nil {
		return err
	}
	if !bytes.Equal(stored.Owner, owner) {
		return types.ErrUnauthorized
	}
	// Keep an expired tombstone so a funded session cannot become an
	// independent primary account after revocation.
	stored.ExpiresAt = 1
	return k.Sessions.Set(ctx, session, stored)
}

func (k Keeper) resolveAuthor(ctx context.Context, signer sdk.AccAddress) (sdk.AccAddress, error) {
	stored, err := k.Sessions.Get(ctx, signer)
	if errors.Is(err, collections.ErrNotFound) {
		return signer, nil
	}
	if err != nil {
		return nil, err
	}
	if sdk.UnwrapSDKContext(ctx).BlockTime().Unix() >= stored.ExpiresAt {
		return nil, types.ErrSessionExpired
	}
	return sdk.AccAddress(stored.Owner), nil
}
