# Obsidian Nvim Handoff

Copy `nvim-handoff/` into `<vault>/.obsidian/plugins/`, enable community
plugins, and enable **Nvim Handoff**. Reload the app once.

`:oo` in Neovim then opens the current vault note with graph view in a right
split and keeps that note selected in the graph. Set `PROTOCOL_VAULT` to the
vault path so Neovim knows which folder to hand off.

Optional: copy `graph-focus.css` into `<vault>/.obsidian/snippets/` and enable
the snippet so the focused note color is easier to see.
