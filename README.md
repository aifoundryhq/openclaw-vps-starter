# OpenClaw Starter Installer

Deploy a clean, localhost-only OpenClaw setup on an Ubuntu VPS in minutes.

This project is a **public starter edition** designed to help developers, builders, and operators get a secure baseline OpenClaw environment running quickly.

It is intentionally simple, useful, and trust-building.

---

## What This Includes

* ✅ Ubuntu VPS installer
* ✅ Docker + Docker Compose setup
* ✅ OpenClaw clone + bootstrap
* ✅ Localhost-only network bindings
* ✅ `.env` generation
* ✅ Health checks
* ✅ Optional UFW firewall enablement
* ✅ Telegram-ready pairing flow
* ✅ Clean post-install summary

---

## What This Does NOT Include

This public starter intentionally excludes advanced premium/internal features such as:

* ❌ Deep troubleshooting automation
* ❌ Repair / upgrade workflows
* ❌ Client presets
* ❌ Advanced hardening packs
* ❌ Deployment support bundles
* ❌ White-glove onboarding

If you'd rather skip setup headaches and get production-ready help fast, see the support section below.

---

## Requirements

* Ubuntu VPS
* Non-root sudo user
* Internet access
* Fresh server recommended

Tested on:

* Ubuntu 22.04+
* Ubuntu 24.04+

---

## Quick Start

SSH into your VPS:

```bash
ssh your-user@your-server-ip
```

Download installer:

```bash
curl -O https://raw.githubusercontent.com/aifoundryhq/openclaw-vps-starter/main/install_openclaw_starter.sh
```

Make executable:

```bash
chmod +x install_openclaw_starter.sh
```

Run installer:

```bash
./install_openclaw_starter.sh
```

---

## One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/aifoundryhq/openclaw-vps-starter/main/install_openclaw_starter.sh | bash
```

---

## Optional Flags

Show help:

```bash
./install_openclaw_starter.sh --help
```

Enable firewall:

```bash
./install_openclaw_starter.sh --enable-ufw
```

Non-interactive mode:

```bash
./install_openclaw_starter.sh --yes
```

Provide tokens during install:

```bash
./install_openclaw_starter.sh \
  --telegram-token "YOUR_TOKEN" \
  --anthropic-key "YOUR_KEY"
```

---

## After Install

Check status:

```bash
cd ~/projects/openclaw && sudo docker compose ps
```

View logs:

```bash
cd ~/projects/openclaw && sudo docker compose logs -f openclaw-gateway
```

Restart services:

```bash
cd ~/projects/openclaw && sudo docker compose restart
```

Stop services:

```bash
cd ~/projects/openclaw && sudo docker compose down
```

---

## Telegram Pairing

If you added a Telegram Bot Token:

Message your bot:

```text
/pair
```

Then approve:

```bash
cd ~/projects/openclaw
sudo docker compose run --rm openclaw-cli pairing approve telegram <PAIR_CODE>
```

---

## Security Defaults

This starter installer uses:

* ✅ Localhost-only port bindings (`127.0.0.1`)
* ✅ Docker restart policy
* ✅ Optional UFW firewall prompt
* ✅ Basic SSH hardening checks
* ✅ Non-root install requirement

---

## Need Help?

Want it deployed faster or customized for your use case?

Book setup help: https://calendly.com/aifoundryhq/setup

---

## Why This Exists

Most people waste hours trying to:

* install Docker correctly
* wire environment variables
* debug container issues
* secure ports
* figure out OpenClaw startup flow

This starter removes friction and gives you a clean baseline.

---

## Roadmap

Planned starter improvements:

* pinned image versions
* auto update checker
* better diagnostics
* improved docs
* optional reverse proxy guide

---

## Disclaimer

This project is unofficial and community-focused.

Use at your own discretion. Always review scripts before running on production systems.

---

## License

MIT License

---

## Built By

### AI Foundry

Helping builders deploy useful AI systems faster.

Follow for more:

* GitHub: https://github.com/aifoundryhq
* YouTube: https://www.youtube.com/@aifoundryhq
* X / Twitter: https://x.com/aifoundryhq?s=21&t=vqGd3w_4Ral6LfAeR8Jviw
