package types

import errorsmod "cosmossdk.io/errors"

var (
	ErrInvalidContent   = errorsmod.Register(ModuleName, 2, "invalid discussion content")
	ErrMessageNotFound  = errorsmod.Register(ModuleName, 3, "discussion message not found")
	ErrParentNotFound   = errorsmod.Register(ModuleName, 4, "discussion parent not found in proposal scope")
	ErrProposalMissing  = errorsmod.Register(ModuleName, 5, "governance proposal not found")
	ErrInvalidReaction  = errorsmod.Register(ModuleName, 6, "invalid discussion reaction")
	ErrInvalidAmount    = errorsmod.Register(ModuleName, 7, "invalid amount")
	ErrInvalidSession   = errorsmod.Register(ModuleName, 8, "invalid discussion session")
	ErrSessionExpired   = errorsmod.Register(ModuleName, 9, "discussion session expired")
	ErrSessionForbidden = errorsmod.Register(
		ModuleName,
		10,
		"session is not authorized for this operation",
	)
	ErrUnauthorized = errorsmod.Register(ModuleName, 11, "unauthorized")
)
