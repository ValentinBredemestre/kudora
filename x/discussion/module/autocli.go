package discussion

import (
	autocliv1 "cosmossdk.io/api/cosmos/autocli/v1"

	"github.com/Kudora-Labs/kudora/x/discussion/types"
)

func (AppModule) AutoCLIOptions() *autocliv1.ModuleOptions {
	return &autocliv1.ModuleOptions{
		Query: &autocliv1.ServiceCommandDescriptor{
			Service: types.Query_serviceDesc.ServiceName,
			RpcCommandOptions: []*autocliv1.RpcCommandOptions{
				{RpcMethod: "Params", Use: "params", Short: "Show discussion parameters"},
				{RpcMethod: "Message", Use: "message [proposal-id] [message-id]", PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "proposal_id"}, {ProtoField: "message_id"}}},
				{RpcMethod: "Messages", Use: "messages [proposal-id]", PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "proposal_id"}}},
				{RpcMethod: "Reactions", Use: "reactions [proposal-id] [message-id]", PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "proposal_id"}, {ProtoField: "message_id"}}},
				{RpcMethod: "Session", Use: "session [session-address]", PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "session_address"}}},
			},
		},
		Tx: &autocliv1.ServiceCommandDescriptor{
			Service: types.Msg_serviceDesc.ServiceName,
			RpcCommandOptions: []*autocliv1.RpcCommandOptions{
				{RpcMethod: "UpdateParams", Skip: true},
				{RpcMethod: "Post", Use: "post [proposal-id] [parent-id] [content]", PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "proposal_id"}, {ProtoField: "parent_id"}, {ProtoField: "content"}}},
				{RpcMethod: "React", Use: "react [proposal-id] [message-id] [reaction]", PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "proposal_id"}, {ProtoField: "message_id"}, {ProtoField: "reaction"}}},
				{RpcMethod: "Zap", Use: "zap [proposal-id] [message-id] [amount-akud]", PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "proposal_id"}, {ProtoField: "message_id"}, {ProtoField: "amount"}}},
				{RpcMethod: "AuthorizeSession", Use: "authorize-session [session-address] [expires-at] [fund-amount-akud]", PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "session_address"}, {ProtoField: "expires_at"}, {ProtoField: "fund_amount"}}},
				{RpcMethod: "RevokeSession", Use: "revoke-session [session-address]", PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "session_address"}}},
			},
		},
	}
}
