const { Plugin, TFile } = require("obsidian");

function rootLeavesOfType(workspace, type) {
    const found = [];
    workspace.iterateRootLeaves((leaf) => {
        if (leaf.view.getViewType() === type) found.push(leaf);
    });
    return found;
}

function sameTabGroup(a, b) {
    return a.parent && a.parent === b.parent && a.parent.type === "tabs";
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function lookupNode(renderer, id) {
    if (!renderer || !id) return null;
    if (renderer.nodeLookup && renderer.nodeLookup[id]) return renderer.nodeLookup[id];
    if (Array.isArray(renderer.nodes)) {
        return renderer.nodes.find((node) => node.id === id) || null;
    }
    return (renderer.nodes && renderer.nodes[id]) || null;
}

module.exports = class NvimHandoff extends Plugin {
    async onload() {
        this.registerObsidianProtocolHandler("nvim", (params) => {
            void this.handle(params);
        });
        this.registerEvent(this.app.workspace.on("file-open", (file) => {
            void this.highlightCurrent(file);
        }));
        this.app.workspace.onLayoutReady(() => {
            void this.highlightCurrent(this.app.workspace.getActiveFile());
        });
    }

    async handle(params) {
        await new Promise((resolve) => this.app.workspace.onLayoutReady(resolve));
        const file = this.resolveFile(params.file || params.path || "");
        await this.ensureNoteAndGraph(file);
        await this.highlightCurrent(file || this.app.workspace.getActiveFile());
    }

    resolveFile(raw) {
        if (!raw) return null;
        let rel = raw.replace(/\\/g, "/").replace(/^\/+/, "");
        const vaultName = this.app.vault.getName();
        if (rel === vaultName || rel.startsWith(vaultName + "/")) {
            rel = rel.slice(vaultName.length).replace(/^\/+/, "");
        }
        const abs = this.app.vault.getAbstractFileByPath(rel);
        return abs instanceof TFile ? abs : null;
    }

    async ensureNoteAndGraph(file) {
        const { workspace } = this.app;
        const graphLeaves = rootLeavesOfType(workspace, "graph");
        let graphLeaf = graphLeaves[0];
        let noteLeaf = rootLeavesOfType(workspace, "markdown")[0];

        if (!noteLeaf) {
            const recent = workspace.getMostRecentLeaf(workspace.rootSplit);
            if (recent && recent.view.getViewType() !== "graph") {
                noteLeaf = recent;
            } else if (graphLeaf) {
                noteLeaf = workspace.createLeafBySplit(graphLeaf, "vertical", true);
            } else {
                noteLeaf = workspace.getLeaf(false);
            }
        }

        if (file) {
            await noteLeaf.openFile(file, { active: true });
        }

        if (!graphLeaf) {
            graphLeaf = workspace.createLeafBySplit(noteLeaf, "vertical", false);
            await graphLeaf.setViewState({ type: "graph", active: false });
        } else if (sameTabGroup(noteLeaf, graphLeaf)) {
            const moved = workspace.createLeafBySplit(noteLeaf, "vertical", false);
            await moved.setViewState({ type: "graph", active: false });
            graphLeaf.detach();
        }

        workspace.setActiveLeaf(noteLeaf, { focus: true });
    }

    async highlightCurrent(file) {
        if (!(file instanceof TFile)) return;
        for (const leaf of rootLeavesOfType(this.app.workspace, "graph")) {
            this.keepHighlightOnUnhover(leaf.view);
            for (let attempt = 0; attempt < 20; attempt++) {
                if (this.applyHighlight(leaf.view, file)) break;
                await sleep(100);
            }
        }
    }

    applyHighlight(view, file) {
        const renderer = view.renderer;
        const engine = view.dataEngine;
        if (!renderer) return false;
        if (engine && engine.currentFocusFile !== file.path) {
            engine.currentFocusFile = file.path;
            if (typeof engine.render === "function") engine.render();
        }
        const node = lookupNode(renderer, file.path);
        if (!node) return false;
        renderer.highlightNode = node;
        if (typeof renderer.changed === "function") renderer.changed();
        return true;
    }

    keepHighlightOnUnhover(view) {
        const renderer = view.renderer;
        if (!renderer || renderer._nvimHandoffUnhover) return;
        renderer._nvimHandoffUnhover = true;
        const previous = renderer.onNodeUnhover;
        renderer.onNodeUnhover = () => {
            if (typeof previous === "function") previous.call(view.dataEngine || view);
            const file = this.app.workspace.getActiveFile();
            if (file instanceof TFile) {
                requestAnimationFrame(() => this.applyHighlight(view, file));
            }
        };
    }
};
