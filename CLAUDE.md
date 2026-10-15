# Paywise

DubHacks '26 project: at checkout, Paywise tells you which of your cards covers this purchase if it breaks or gets stolen, and what that costs in cash back. Spec: `SPEC.md`.

## Rules

- Never commit secrets: API keys, tokens, or `.env` files. Put placeholder values in `.env.example`.
- Never put real card numbers, account numbers, or personal financial data in code, tests, fixtures, or logs. Use sample data that is obviously fake.
- Keep card data (reward rates, annual fees, bonus categories) in one data file. Don't hard-code it in the recommendation logic.

## Working with Claude

- When a step doesn't need our input, keep going. Stop and ask only when you can't continue without us, or before anything destructive or hard to undo: force-pushing, deleting branches or files, rewriting history, or changing repo settings or secrets.
- For long, multi-step tasks, keep a checklist in `TASKS.md` and update it as you go, so progress survives when older context gets summarized. `TASKS.md` is gitignored, so don't commit it.
- When you use subagents, check the evidence they report before you accept it.
- When you review code, list only problems you'd block the merge for. For each one, give the file and line, and how to show it fails.
- When you report facts or research, mark anything you couldn't confirm and say where you looked.
- End each task with three short headings: **Blocked on me** (what you need from us, or "nothing"), **Changed**, and **Found**.
