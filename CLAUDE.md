# Credit Card Recommender

Hackathon 2026 project: recommend the best credit card for a user based on their spending habits and goals.

## Status

The stack isn't chosen yet. It may be a browser extension (TypeScript) or a web app (Python or Node). Once it's decided, add how to install, run, and test the project here.

## Workflow

- Branch off `main` as `feature/<short-name>` and open a pull request into `main`.
- Push branches to this repo, not a fork. Pull requests from forks don't get the review bot's secret, so they aren't reviewed.
- Open a pull request as a draft while you're still working, then mark it ready for review. Claude reviews it once at that point. For another review after you push fixes, comment `@claude review the latest changes`.
- A teammate approves every pull request before it merges. Claude's review doesn't replace that.

## Rules

- Never commit secrets: API keys, tokens, or `.env` files. Put placeholder values in `.env.example`.
- Never put real card numbers, account numbers, or personal financial data in code, tests, fixtures, or logs. Use sample data that is obviously fake.
- Keep card data (reward rates, annual fees, bonus categories) in one data file. Don't hard-code it in the recommendation logic.
