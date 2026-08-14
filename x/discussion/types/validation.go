package types

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"
	"unicode/utf8"

	sdkmath "cosmossdk.io/math"
	"github.com/ethereum/go-ethereum/common"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

var contentTypes = map[string]struct{}{
	"budget":   {},
	"carousel": {},
	"poll":     {},
	"text":     {},
	"timeline": {},
}

func ValidateContent(content []byte) error {
	if len(content) == 0 || len(content) > MaxContentBytes || !utf8.Valid(content) {
		return ErrInvalidContent.Wrapf("payload must be valid UTF-8 between 1 and %d bytes", MaxContentBytes)
	}

	var payload map[string]any
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.UseNumber()
	if err := decoder.Decode(&payload); err != nil {
		return ErrInvalidContent.Wrap("payload must be valid JSON")
	}
	version, ok := payload["v"].(json.Number)
	if !ok || version.String() != "1" {
		return ErrInvalidContent.Wrap("payload version must be 1")
	}
	kind, ok := payload["t"].(string)
	if !ok {
		return ErrInvalidContent.Wrap("payload type is required")
	}
	if _, ok := contentTypes[kind]; !ok {
		return ErrInvalidContent.Wrapf("unknown payload type %q", kind)
	}
	if containsImageData(payload) {
		return ErrInvalidContent.Wrap("image and base64 data are not supported")
	}

	var compact bytes.Buffer
	if err := json.Compact(&compact, content); err != nil || !bytes.Equal(compact.Bytes(), content) {
		return ErrInvalidContent.Wrap("payload must be canonical minified JSON")
	}
	return nil
}

func containsImageData(value any) bool {
	switch typed := value.(type) {
	case map[string]any:
		for key, child := range typed {
			normalized := strings.ToLower(key)
			if normalized == "image" || normalized == "images" || normalized == "avatar" || normalized == "base64" {
				return true
			}
			if containsImageData(child) {
				return true
			}
		}
	case []any:
		for _, child := range typed {
			if containsImageData(child) {
				return true
			}
		}
	case string:
		lower := strings.ToLower(typed)
		return strings.HasPrefix(lower, "data:image/") || strings.Contains(lower, ";base64,")
	}
	return false
}

func ParseCreator(value string) (sdk.AccAddress, error) {
	address, err := sdk.AccAddressFromBech32(value)
	if err != nil || len(address) != common.AddressLength {
		return nil, fmt.Errorf("invalid creator address")
	}
	return address, nil
}

func ParseAccountAddress(value string) (sdk.AccAddress, error) {
	if common.IsHexAddress(value) {
		address := common.HexToAddress(value)
		if address == (common.Address{}) {
			return nil, ErrInvalidSession.Wrap("zero address is not allowed")
		}
		return sdk.AccAddress(address.Bytes()), nil
	}
	address, err := ParseCreator(value)
	if err != nil {
		return nil, ErrInvalidSession.Wrap("expected an EVM or Kudora account address")
	}
	return address, nil
}

func ParsePositiveAmount(value string) (sdkmath.Int, error) {
	amount, ok := sdkmath.NewIntFromString(value)
	if !ok || !amount.IsPositive() {
		return sdkmath.Int{}, ErrInvalidAmount.Wrap("amount must be a positive integer in akud")
	}
	return amount, nil
}
