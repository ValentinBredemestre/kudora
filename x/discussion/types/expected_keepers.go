package types

import (
	"context"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

// BankKeeper is the minimal bank surface used by the current discussion flows.
type BankKeeper interface {
	GetBalance(context.Context, sdk.AccAddress, string) sdk.Coin
	SendCoins(context.Context, sdk.AccAddress, sdk.AccAddress, sdk.Coins) error
	SendCoinsFromAccountToModule(context.Context, sdk.AccAddress, string, sdk.Coins) error
}
