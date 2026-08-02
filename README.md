# Faction Ledger

A focused Torn City faction budget tracker for distributing proceeds across earmarked accounts and maintaining a clear financial audit trail.

## Features

- Percentage-based automatic distribution of faction proceeds
- Custom accounts with editable names and allocation percentages
- Spending and transfers with overdraft protection
- Durable transaction history backed by Cloudflare D1
- Responsive treasury dashboard for desktop and mobile

## Local development

Requires Node.js 22.13 or newer.

```bash
npm ci
npm run dev
```

Use `npm run build` for a production build, `npm run db:generate` after schema changes, and `node --test tests/rendered-html.test.mjs` for the focused checks.
