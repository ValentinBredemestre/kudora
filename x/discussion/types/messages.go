package types

func (msg MsgUpdateParams) ValidateBasic() error {
	if _, err := ParseCreator(msg.Authority); err != nil {
		return err
	}
	return msg.Params.Validate()
}

func (msg MsgPost) ValidateBasic() error {
	if _, err := ParseCreator(msg.Creator); err != nil {
		return err
	}
	return ValidateContent(msg.Content)
}

func (msg MsgReact) ValidateBasic() error {
	if _, err := ParseCreator(msg.Creator); err != nil {
		return err
	}
	if msg.MessageId == 0 {
		return ErrMessageNotFound
	}
	if msg.Reaction < Reaction_REACTION_UNSPECIFIED || msg.Reaction > Reaction_REACTION_NOT_USEFUL {
		return ErrInvalidReaction
	}
	return nil
}

func (msg MsgZap) ValidateBasic() error {
	if _, err := ParseCreator(msg.Creator); err != nil {
		return err
	}
	if msg.MessageId == 0 {
		return ErrMessageNotFound
	}
	_, err := ParsePositiveAmount(msg.Amount)
	return err
}

func (msg MsgAuthorizeSession) ValidateBasic() error {
	owner, err := ParseCreator(msg.Creator)
	if err != nil {
		return err
	}
	session, err := ParseAccountAddress(msg.SessionAddress)
	if err != nil {
		return err
	}
	if owner.Equals(session) {
		return ErrInvalidSession.Wrap("session must differ from owner")
	}
	_, err = ParsePositiveAmount(msg.FundAmount)
	return err
}

func (msg MsgRevokeSession) ValidateBasic() error {
	if _, err := ParseCreator(msg.Creator); err != nil {
		return err
	}
	_, err := ParseAccountAddress(msg.SessionAddress)
	return err
}
