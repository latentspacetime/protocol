#!/bin/zsh
# Headless behavior tests for the vendored Neovim modules. The suite loads
# only the modules each test needs, so validation never installs plugins.

set -eu
root="${0:A:h:h}"
sandbox="$(mktemp -d)"
sandbox="${sandbox:A}"
trap 'rm -rf "$sandbox"' EXIT

mkdir -p "$sandbox/home" "$sandbox/state"
print -r -- "source ${(q)root}/shell/protocol.zsh" > "$sandbox/home/.zshrc"

export HOME="$sandbox/home"
export XDG_STATE_HOME="$sandbox/state"
export LUA_PATH="$root/nvim/lua/?.lua;;"
export PROTOCOL_ROOT="$root"

run_nvim_test() {
  local setup="$1" test_file="$2"
  env -u NVIM nvim --headless -u NONE "$root/nvim/init.lua" \
    -c "lua vim.g.mapleader = ' '; $setup" \
    -c "luafile $root/nvim/tests/$test_file"
}

run_nvim_test 'require("recover"); require("keymaps")' recover_test.lua
run_nvim_test 'require("otemp")' otemp_test.lua
run_nvim_test 'require("friction")' friction_test.lua
run_nvim_test 'require("appearance")' tabslot_test.lua
run_nvim_test 'require("menus"); require("search")' repository_picker_test.lua

print "nvim tests passed"
