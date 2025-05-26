// File: src/executor.rs
// ---------------------
use crate::models::{Play, Task};
use crate::result_store::CommandResult;
use tokio::process::Command;

/// 执行单个任务数组（来自 Playbook 的 tasks）
pub async fn apply(tasks: Vec<Task>) -> anyhow::Result<Vec<CommandResult>> {
    let mut results = vec![];
    for task in tasks {
        let (cmd_str, cmd_type) = if let Some(shell_cmd) = &task.shell {
            (shell_cmd.clone(), "shell")
        } else if let Some(script_path) = &task.script {
            (script_path.clone(), "script")
        } else {
            results.push(CommandResult {
                task: task.name,
                stdout: "".into(),
                stderr: "unsupported task type".into(),
                success: false,
                return_code: 1,
            });
            continue;
        };

        let output = if cmd_type == "shell" {
            Command::new("sh")
                .arg("-c")
                .arg(&cmd_str)
                .output()
                .await?
        } else {
            Command::new("sh")
                .arg(&cmd_str)
                .output()
                .await?
        };

        results.push(CommandResult {
            task: task.name,
            stdout: String::from_utf8_lossy(&output.stdout).into(),
            stderr: String::from_utf8_lossy(&output.stderr).into(),
            success: output.status.success(),
            return_code: output.status.code().unwrap_or(-1),
        });
    }
    Ok(results)
}

/// 执行完整的本地 Playbook（多个 Play，每个包含多个 task）
pub async fn run(playbook: Vec<Play>) -> anyhow::Result<Vec<CommandResult>> {
    let mut all_results = vec![];
    for play in playbook {
        println!("🎯 Play: {}", play.name);
        let results = apply(play.tasks).await?;
        for res in &results {
            println!("▶ {} | rc={}\nstdout: {}\nstderr: {}\n",
                res.task, res.return_code, res.stdout.trim(), res.stderr.trim());
        }
        all_results.extend(results);
    }
    Ok(all_results)
}
