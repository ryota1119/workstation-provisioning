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
tasks="$repo_root/roles/workspace-repositories/tasks/main.yml"

for repository in hn-mcp qiita-mcp zenn-mcp socialdata-mcp; do
  assert_contains "$variables" "name: \"$repository\""
  assert_contains "$variables" "repo: \"github.com/RayLabOrg/$repository\""
  assert_contains "$tasks" "{{ workspace_repositories_root }}/{{ item.item.repo }}"
done

assert_contains "$variables" 'workspace_repositories_root: "{{ ansible_env.HOME }}/Workspace/repos"'
assert_contains "$tasks" 'ghq'
assert_contains "$tasks" '--update'
assert_contains "$tasks" '-p'
assert_contains "$tasks" 'uv'
assert_contains "$tasks" 'sync'
assert_contains "$tasks" '--frozen'
assert_contains "$tasks" '    - install'
assert_contains "$tasks" '    - upgrade'
assert_contains "$tasks" '    - workspace-repositories'
assert_contains "$repo_root/site.yml" '- role: workspace-repositories'
assert_contains "$repo_root/Makefile" '.PHONY: workspace-repositories'
assert_contains "$repo_root/Makefile" 'site.yml --tags "workspace-repositories"'

printf '%s\n' "workspace-repositories tests passed"
