package cmd

import (
	"testing"

	"github.com/spf13/cobra"
)

func findSubcommandByName(cmdName string, cmds []*cobra.Command) *cobra.Command {
	for _, sub := range cmds {
		if sub.Name() == cmdName {
			return sub
		}
	}

	return nil
}

func TestRootCmdExposesExpectedModuleCommands(t *testing.T) {
	rootCmd := NewRootCmd()

	queryCmd := findSubcommandByName("query", rootCmd.Commands())
	if queryCmd == nil {
		t.Fatal("query command not found")
	}

	txCmd := findSubcommandByName("tx", rootCmd.Commands())
	if txCmd == nil {
		t.Fatal("tx command not found")
	}

	for _, name := range []string{"bank", "gov", "wasm", "integrity"} {
		if findSubcommandByName(name, queryCmd.Commands()) == nil {
			t.Fatalf("query %s command not found", name)
		}
		if findSubcommandByName(name, txCmd.Commands()) == nil {
			t.Fatalf("tx %s command not found", name)
		}
	}
}
