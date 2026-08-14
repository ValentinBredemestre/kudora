package keeper

import (
	"bytes"
	"context"

	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/Kudora-Labs/kudora/x/discussion/types"
)

type msgServer struct{ Keeper }

var _ types.MsgServer = msgServer{}

func NewMsgServerImpl(k Keeper) types.MsgServer { return msgServer{Keeper: k} }

func (m msgServer) UpdateParams(ctx context.Context, msg *types.MsgUpdateParams) (*types.MsgUpdateParamsResponse, error) {
	authority, err := m.addressCodec.StringToBytes(msg.Authority)
	if err != nil {
		return nil, err
	}
	if !bytes.Equal(authority, m.authority) {
		return nil, types.ErrUnauthorized
	}
	if err := msg.Params.Validate(); err != nil {
		return nil, err
	}
	return &types.MsgUpdateParamsResponse{}, m.Params.Set(ctx, msg.Params)
}

func (m msgServer) Post(ctx context.Context, msg *types.MsgPost) (*types.MsgPostResponse, error) {
	creator, err := m.addressCodec.StringToBytes(msg.Creator)
	if err != nil {
		return nil, err
	}
	id, err := m.Keeper.Post(ctx, sdk.AccAddress(creator), msg.ProposalId, msg.ParentId, msg.Content)
	if err != nil {
		return nil, err
	}
	return &types.MsgPostResponse{MessageId: id}, nil
}

func (m msgServer) React(ctx context.Context, msg *types.MsgReact) (*types.MsgReactResponse, error) {
	creator, err := m.addressCodec.StringToBytes(msg.Creator)
	if err != nil {
		return nil, err
	}
	if err := m.Keeper.React(ctx, sdk.AccAddress(creator), msg.ProposalId, msg.MessageId, msg.Reaction); err != nil {
		return nil, err
	}
	return &types.MsgReactResponse{}, nil
}

func (m msgServer) Zap(ctx context.Context, msg *types.MsgZap) (*types.MsgZapResponse, error) {
	creator, err := m.addressCodec.StringToBytes(msg.Creator)
	if err != nil {
		return nil, err
	}
	amount, err := types.ParsePositiveAmount(msg.Amount)
	if err != nil {
		return nil, err
	}
	if err := m.Keeper.Zap(ctx, sdk.AccAddress(creator), msg.ProposalId, msg.MessageId, amount); err != nil {
		return nil, err
	}
	return &types.MsgZapResponse{}, nil
}

func (m msgServer) AuthorizeSession(ctx context.Context, msg *types.MsgAuthorizeSession) (*types.MsgAuthorizeSessionResponse, error) {
	owner, err := m.addressCodec.StringToBytes(msg.Creator)
	if err != nil {
		return nil, err
	}
	session, err := types.ParseAccountAddress(msg.SessionAddress)
	if err != nil {
		return nil, err
	}
	amount, err := types.ParsePositiveAmount(msg.FundAmount)
	if err != nil {
		return nil, err
	}
	if err := m.Keeper.AuthorizeSession(ctx, sdk.AccAddress(owner), session, msg.ExpiresAt, amount); err != nil {
		return nil, err
	}
	return &types.MsgAuthorizeSessionResponse{}, nil
}

func (m msgServer) RevokeSession(ctx context.Context, msg *types.MsgRevokeSession) (*types.MsgRevokeSessionResponse, error) {
	owner, err := m.addressCodec.StringToBytes(msg.Creator)
	if err != nil {
		return nil, err
	}
	session, err := types.ParseAccountAddress(msg.SessionAddress)
	if err != nil {
		return nil, err
	}
	if err := m.Keeper.RevokeSession(ctx, sdk.AccAddress(owner), session); err != nil {
		return nil, err
	}
	return &types.MsgRevokeSessionResponse{}, nil
}
