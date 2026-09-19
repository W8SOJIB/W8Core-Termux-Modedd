# Cline

Autonomous coding agent CLI — capable of creating/editing files, running commands, using browser, and more.

**Package:** cline  
**Author:** DevCoreX  
**Repository:** https://github.com/W8SOJIB/W8Core-Termux-Moded  
**Official:** https://github.com/cline/cline  
**Type:** AI coding agent CLI (Node.js / npm)  
**License:** Apache-2.0

## Description

Cline is an autonomous coding agent that runs right in your terminal. It can plan, write, and edit code across your project, run commands, and integrate with multiple AI providers (OpenRouter, Anthropic, OpenAI, etc.).

## Dependencies

- **Native mode:** Node.js (v20+ / nodejs-lts), git, ripgrep, curl, ca-certificates
- **Proot mode:** proot-distro (Ubuntu container), Node.js, npm, curl, ca-certificates

## Install

```bash
core install ai --cline
```

Or run interactive AI menu:
```bash
core install ai
```

## Uninstall

```bash
core uninstall ai --cline
```

## Update

```bash
core update ai --cline
```

## Usage

Authenticate or configure provider:
```bash
cline auth
```

Start interactive session:
```bash
cline
```

Run a task directly:
```bash
cline "your task prompt here"
```
