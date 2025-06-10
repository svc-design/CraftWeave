package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "craftweave",
	Short: "CraftWeave - 执行与编织任务和架构的现代工具",
	Long:  `CraftWeave 是一个现代化的 DevOps CLI 工具，融合任务执行、架构编排、拓扑建模与插件生态。`,
	Run: func(cmd *cobra.Command, args []string) {
		printBanner()
	},
}

// 入口函数
func Execute() {
	cobra.CheckErr(rootCmd.Execute())
}

func init() {
	rootCmd.CompletionOptions.DisableDefaultCmd = true

	// 添加全局子命令
	rootCmd.AddCommand(ansibleCmd)
	rootCmd.AddCommand(playbookCmd)
	rootCmd.AddCommand(vaultCmd)
	rootCmd.AddCommand(cmdbCmd)
	rootCmd.AddCommand(pluginCmd)

	// 注册全局标志（所有子命令可用）
	rootCmd.PersistentFlags().BoolVarP(
		&AggregateOutput,
		"aggregate", "A",
		false,
		"Aggregate output from multiple hosts",
	)

	rootCmd.PersistentFlags().IntVarP(
		&MaxConcurrency,
		"forks", "f",
		5,
		"Maximum number of parallel tasks",
	)
}

// 启动时打印 ASCII Banner
func printBanner() {
	content, err := os.ReadFile("banner.txt")
	if err == nil {
		fmt.Println(string(content))
	}
}
