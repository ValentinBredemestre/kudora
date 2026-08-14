package types

import "cosmossdk.io/collections"

const (
	ModuleName = "discussion"
	StoreKey   = ModuleName

	MaxContentBytes             = 8 * 1024
	NativeDenom                 = "akud"
	DiscussionPrecompileAddress = "0x0000000000000000000000000000000000000900"
)

var (
	ParamsKey        = collections.NewPrefix(0)
	NextMessageIDKey = collections.NewPrefix(1)
	MessageKey       = collections.NewPrefix(2)
	ReactionKey      = collections.NewPrefix(3)
	SessionKey       = collections.NewPrefix(4)
)
