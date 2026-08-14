package types

import (
	"fmt"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

func DefaultParams() Params {
	return Params{PostFee: sdk.NewInt64Coin(NativeDenom, 1_000_000_000_000_000)}
}

func (p Params) Validate() error {
	if !p.PostFee.IsValid() || !p.PostFee.IsPositive() {
		return fmt.Errorf("post fee must be a positive valid coin")
	}
	if p.PostFee.Denom != NativeDenom {
		return fmt.Errorf("post fee denom must be %s", NativeDenom)
	}
	return nil
}
