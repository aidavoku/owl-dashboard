#!/bin/bash
# Deploy to Cloudflare Pages via Wrangler
cd "$(dirname "$0")"

# Check if wrangler is installed
if ! command -v wrangler &>/dev/null; then
  npm install -g wrangler
fi

# Login (first time only)
# wrangler login

# Deploy to Pages
wrangler pages deploy . --project-name=owl-dashboard --branch=main
