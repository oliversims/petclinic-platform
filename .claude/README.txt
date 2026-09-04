.claude — what each subfolder does
==================================

skills/
  Named workflows you start (slash commands).
  Claude follows the steps in that skill’s SKILL.md.
  Example: skills/terraform-plan/ → /terraform-plan dev
           runs init + plan for the dev environment.


agents/
  Specialist reviewers Claude can launch.
  They inspect code and report issues. They do not edit files.
  Example: agents/terraform-reviewer.md
           checks Terraform for security, tags, and cost problems.


rules/
  Conventions loaded automatically when Claude edits matching files.
  So new code follows this repo’s standards.
  Example: rules/terraform.md
           applies when editing terraform/**/*.tf
           (naming, tags, required module files, …).


hooks/
  Small scripts that run around Claude’s tool use.
  They can block a dangerous command or warn you.
  Example: hooks/block-destroy.sh
           stops Claude from running terraform destroy.


settings.json
  Shared project settings for Claude in this repo.
  Wires which hooks run (before/after tool use).
  Committed so everyone gets the same guards.
  Example: PreToolUse runs hooks/block-destroy.sh
           so Claude cannot run terraform destroy.


settings.local.json
  Your machine-only Claude settings (not for the team).
  Things like AWS profile/region, allowed commands, MCP servers.
  Keep local — do not rely on it for shared safety rules.
  Example: AWS_REGION = us-east-1, AWS_PROFILE = default
           and which MCP servers you enable on this machine.
