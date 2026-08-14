package types

import "fmt"

func DefaultGenesis() *GenesisState {
	return &GenesisState{
		Params:        DefaultParams(),
		NextMessageId: 1,
	}
}

func (gs GenesisState) Validate() error {
	if err := gs.Params.Validate(); err != nil {
		return err
	}
	if gs.NextMessageId == 0 {
		return fmt.Errorf("next message id must be positive")
	}
	seenMessages := make(map[[2]uint64]struct{}, len(gs.Messages))
	for _, message := range gs.Messages {
		if message.MessageId == 0 || message.MessageId >= gs.NextMessageId {
			return fmt.Errorf("invalid genesis message id %d", message.MessageId)
		}
		if len(message.Author) != 20 {
			return fmt.Errorf("invalid genesis message author")
		}
		if err := ValidateContent(message.Content); err != nil {
			return err
		}
		key := [2]uint64{message.ProposalId, message.MessageId}
		if _, exists := seenMessages[key]; exists {
			return fmt.Errorf("duplicate genesis message")
		}
		seenMessages[key] = struct{}{}
	}
	for _, reaction := range gs.Reactions {
		if _, exists := seenMessages[[2]uint64{reaction.ProposalId, reaction.MessageId}]; !exists {
			return fmt.Errorf("genesis reaction references missing message")
		}
		if len(reaction.Account) != 20 || reaction.Reaction == Reaction_REACTION_UNSPECIFIED {
			return fmt.Errorf("invalid genesis reaction")
		}
	}
	for _, session := range gs.Sessions {
		if len(session.Session) != 20 || len(session.Owner) != 20 || session.ExpiresAt <= 0 {
			return fmt.Errorf("invalid genesis session")
		}
	}
	return nil
}
