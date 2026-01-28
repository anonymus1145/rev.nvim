# rev.nvim

`rev.nvim` is a Neovim plugin that automatically reviews your recent code changes using a Large Language Model (LLM) and Git. It provides actionable recommendations, categorizes them by severity, and can even apply the suggested changes for you.

## Features

- Analyze your latest Git changes (`git diff`) using an LLM.  
- Categorize recommendations into:  
  - **Critical changes** – must-fix issues.  
  - **Warnings** – suggested improvements.  
- Interactive workflow:  
  - Review LLM suggestions before applying.  
  - Choose to apply recommended changes or continue without them.  
- Automatic Git operations:  
  - Apply changes (`git add`, `git commit`) automatically.  
  - Perform `git pull` to ensure your branch is up-to-date or prompt for rebase if needed.  
- Fully integrated into Neovim for a seamless developer experience.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'anonymus1145/rev.nvim',
  dependencies = { 'nvim-lua/lazy.nvim' },
  config = function()
    require('llm_code_review').setup()
  end
}
## License MIT
