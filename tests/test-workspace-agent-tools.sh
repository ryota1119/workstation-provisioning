#!/bin/bash

set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

assert_contains() {
  local file=$1
  local expected=$2

  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Expected %s in %s\n' "$expected" "$file" >&2
    exit 1
  fi
}

variables="$repo_root/group_vars/all.yml"
tasks="$repo_root/roles/workspace-agent-tools/tasks/main.yml"

assert_contains "$variables" 'workspace_agent_tool_name: "claude-obsidian"'
assert_contains "$variables" 'workspace_agent_tool_repo: "github.com/AgriciDaniel/claude-obsidian"'
assert_contains "$variables" 'workspace_agent_tool_checkout: "{{ workspace_repositories_root }}/github.com/AgriciDaniel/claude-obsidian"'
assert_contains "$tasks" 'ghq'
assert_contains "$tasks" 'get'
assert_contains "$tasks" '--update'
assert_contains "$tasks" '-p'
assert_contains "$tasks" '"{{ workspace_agent_tool_repo }}"'
assert_contains "$tasks" 'bin/setup-multi-agent.sh'
assert_contains "$tasks" '--host'
assert_contains "$tasks" 'opencode'
assert_contains "$tasks" '--apply'
assert_contains "$tasks" '--check'
assert_contains "$tasks" '    - install'
assert_contains "$tasks" '    - upgrade'
assert_contains "$tasks" '    - workspace-agent-tools'
assert_contains "$repo_root/site.yml" '- role: workspace-agent-tools'
assert_contains "$repo_root/Makefile" '.PHONY: workspace-agent-tools'
assert_contains "$repo_root/Makefile" 'site.yml --tags "workspace-agent-tools"'

printf '%s\n' "workspace-agent-tools tests passed"
