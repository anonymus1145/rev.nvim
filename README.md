# rev.nvim

rev.nvim is a lightweight, asynchronous Neovim plugin that brings LLM-powered code reviews directly into your editor. It analyzes your staged and unstaged Git changes, generates an intelligent review prompt, and displays insights in a beautiful side-by-side Markdown buffer—all without locking up your UI.

## Features

- Asynchronous Execution: Uses Neovim's vim.system and uv timers so your editor stays responsive while the LLM thinks.
- Chain-of-Thought Prompting: Instead of a static prompt, it first asks the LLM to generate the best possible review criteria for your specific diff before performing the analysis.
- Live UI Feedback: Includes a smooth terminal-style spinner so you know exactly when your insights are landing.
- Context-Aware: Captures 20 lines of context (-U20) around your changes to give the LLM a better understanding of your code.
- Zero Dependencies: No heavy Lua libraries required—just Neovim, curl, and git.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'anonymus1145/rev.nvim',
  -- Ensure environment variables are set
  cond = function()
    return (os.getenv("REVNVIM_API_KEY") ~= nil and os.getenv("REVNVIM_MODEL") and os.getenv("REVNVIM_URL"))
  end
}
```

## Configuration (Environment Variables)

The plugin relies on two environment variables. You can export these in your .zshrc or .bashrc:

```bash
export REVNVIM_API_KEY="api_key"
export REVNVIM_MODEL="llm_model"
export REVNVIM_URL="model_api"
```

## Usage

The plugin comes with a built-in keymap to start the review process immediately:

```lua
  <leader>rv
```

Triggers the diff analysis and opens the review split

## License MIT
