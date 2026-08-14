package keeper

import (
	"context"
	"errors"

	"cosmossdk.io/collections"

	"github.com/cosmos/cosmos-sdk/types/query"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/Kudora-Labs/kudora/x/discussion/types"
)

type queryServer struct{ k Keeper }

var _ types.QueryServer = queryServer{}

func NewQueryServerImpl(k Keeper) types.QueryServer { return queryServer{k: k} }

func (q queryServer) Params(ctx context.Context, req *types.QueryParamsRequest) (*types.QueryParamsResponse, error) {
	if req == nil {
		return nil, status.Error(codes.InvalidArgument, "invalid request")
	}
	params, err := q.k.Params.Get(ctx)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	return &types.QueryParamsResponse{Params: params}, nil
}

func (q queryServer) Message(ctx context.Context, req *types.QueryMessageRequest) (*types.QueryMessageResponse, error) {
	if req == nil || req.MessageId == 0 {
		return nil, status.Error(codes.InvalidArgument, "message id is required")
	}
	stored, err := q.k.GetMessage(ctx, req.ProposalId, req.MessageId)
	if err != nil {
		if errors.Is(err, types.ErrMessageNotFound) {
			return nil, status.Error(codes.NotFound, err.Error())
		}
		return nil, status.Error(codes.Internal, err.Error())
	}
	return &types.QueryMessageResponse{Message: messageView(req.ProposalId, req.MessageId, stored)}, nil
}

func (q queryServer) Messages(ctx context.Context, req *types.QueryMessagesRequest) (*types.QueryMessagesResponse, error) {
	if req == nil {
		return nil, status.Error(codes.InvalidArgument, "invalid request")
	}
	messages, pagination, err := query.CollectionPaginate(
		ctx,
		q.k.Messages,
		req.Pagination,
		func(key collections.Pair[uint64, uint64], stored types.StoredMessage) (types.Message, error) {
			return messageView(key.K1(), key.K2(), stored), nil
		},
		query.WithCollectionPaginationPairPrefix[uint64, uint64](req.ProposalId),
	)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	return &types.QueryMessagesResponse{Messages: messages, Pagination: pagination}, nil
}

func (q queryServer) Reactions(ctx context.Context, req *types.QueryReactionsRequest) (*types.QueryReactionsResponse, error) {
	if req == nil || req.MessageId == 0 {
		return nil, status.Error(codes.InvalidArgument, "message id is required")
	}
	if _, err := q.k.GetMessage(ctx, req.ProposalId, req.MessageId); err != nil {
		return nil, status.Error(codes.NotFound, err.Error())
	}
	prefix := messageKey(req.ProposalId, req.MessageId)
	reactions, pagination, err := query.CollectionPaginate(
		ctx,
		q.k.Reactions,
		req.Pagination,
		func(key collections.Pair[collections.Pair[uint64, uint64], []byte], value uint32) (types.ReactionEntry, error) {
			return types.ReactionEntry{
				ProposalId: key.K1().K1(),
				MessageId:  key.K1().K2(),
				Account:    append([]byte(nil), key.K2()...),
				Reaction:   types.Reaction(value),
			}, nil
		},
		query.WithCollectionPaginationPairPrefix[collections.Pair[uint64, uint64], []byte](prefix),
	)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	return &types.QueryReactionsResponse{Reactions: reactions, Pagination: pagination}, nil
}

func (q queryServer) Session(ctx context.Context, req *types.QuerySessionRequest) (*types.QuerySessionResponse, error) {
	if req == nil {
		return nil, status.Error(codes.InvalidArgument, "invalid request")
	}
	address, err := types.ParseAccountAddress(req.SessionAddress)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	stored, err := q.k.GetSession(ctx, address)
	if err != nil {
		return nil, status.Error(codes.NotFound, err.Error())
	}
	return &types.QuerySessionResponse{Session: types.Session{
		Session:   append([]byte(nil), address...),
		Owner:     append([]byte(nil), stored.Owner...),
		ExpiresAt: stored.ExpiresAt,
	}}, nil
}

func messageView(proposalID, messageID uint64, stored types.StoredMessage) types.Message {
	return types.Message{
		ProposalId: proposalID,
		MessageId:  messageID,
		Author:     append([]byte(nil), stored.Author...),
		ParentId:   stored.ParentId,
		CreatedAt:  stored.CreatedAt,
		Content:    append([]byte(nil), stored.Content...),
	}
}
