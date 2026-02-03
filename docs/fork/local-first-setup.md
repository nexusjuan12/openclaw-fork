# Local-First Setup Guide

Run OpenClaw entirely on free, self-hosted infrastructure: Ollama for LLM inference, SearXNG for web search, and Ollama embeddings for memory.

## Architecture

```
GPU Machine (Windows/Linux)           VPS (Ubuntu 22.04)
  Ollama serving:                       openclaw-fork
    - qwen3:14b (inference)             SearXNG (web search)
    - nomic-embed-text (embeddings)     SQLite (memory store)
         |                                   |
         +--- SSH reverse tunnel (port 11434) ---+
```

The GPU machine runs Ollama with your models. The VPS runs OpenClaw and SearXNG. A reverse SSH tunnel connects them.

## Prerequisites

- **VPS**: Ubuntu 22.04+, 8+ cores, 12+ GB RAM
- **GPU machine**: NVIDIA GPU with 16+ GB VRAM (e.g., P100, RTX 3090, RTX 4090)
- **Ollama** installed on the GPU machine: https://ollama.ai
- SSH access between the machines

## Quick Start (automated)

Run the setup script as root on a fresh VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/nexusjuan12/openclaw-fork/main/scripts/setup-local-first.sh | bash
```

Or clone first and run locally:

```bash
git clone https://github.com/nexusjuan12/openclaw-fork.git ~/openclaw-fork
sudo bash ~/openclaw-fork/scripts/setup-local-first.sh
```

The script creates an `openclaw` user, installs all dependencies, builds the fork, sets up SearXNG, and writes the config.

## Manual Setup

### 1. GPU Machine: Create custom model with 16K context

Pull the base model:

```bash
ollama pull qwen3:14b
ollama pull nomic-embed-text
```

Create a Modelfile to override context window (required for OpenClaw):

```bash
cat > Modelfile <<EOF
FROM qwen3:14b
PARAMETER num_ctx 16384
EOF

ollama create qwen3-16k -f Modelfile
```

Verify the model was created with correct context:

```bash
curl http://localhost:11434/api/show -d '{"name":"qwen3-16k"}' | grep num_ctx
# Should show: "num_ctx": 16384
```

### 2. VPS: Install SearXNG

```bash
sudo bash scripts/install-searxng.sh
```

Verify:

```bash
curl 'http://127.0.0.1:8888/search?q=hello&format=json'
```

### 3. Start the reverse tunnel

From the **GPU machine** (Windows or Linux):

```bash
ssh -N -R 11434:localhost:11434 openclaw@your-vps-ip
```

For a persistent tunnel, use autossh:

```bash
# Install: sudo apt install autossh (Linux) or choco install autossh (Windows)
autossh -M 0 -N -R 11434:localhost:11434 openclaw@your-vps-ip
```

Verify from the VPS:

```bash
curl http://127.0.0.1:11434/api/tags
```

### 4. VPS: Configure OpenClaw

The setup script writes this config to `~/.openclaw/openclaw.json`. For manual setup:

```json5
{
  models: {
    mode: "merge",
    providers: {
      ollama: {
        baseUrl: "http://127.0.0.1:11434/v1",
        apiKey: "ollama-local",
        api: "openai-completions",
        models: [
          {
            id: "qwen3-16k",
            name: "Qwen3 14B (16K)",
            reasoning: false,  // IMPORTANT: Ollama doesn't support extended thinking modes
            input: ["text"],
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
            contextWindow: 16384,
            maxTokens: 4096,
          },
        ],
      },
    },
  },
  agents: {
    defaults: {
      model: { primary: "ollama/qwen3-16k" },
      memorySearch: {
        enabled: false  // Disable for initial setup; can enable later with embeddings
      },
    },
  },
  tools: {
    web: {
      search: {
        provider: "searxng",
        searxng: {
          baseUrl: "http://127.0.0.1:8888",
        },
      },
    },
  },
}
```

Set the environment variable:

```bash
export OLLAMA_API_KEY="ollama-local"
# Add to ~/.profile for persistence
```

### 5. Verify

```bash
cd ~/openclaw-fork

# Check model is available
pnpm openclaw models list

# Test web search (via SearXNG)
curl 'http://127.0.0.1:8888/search?q=weather+today&format=json' | head -c 500

# Test Ollama connectivity
curl http://127.0.0.1:11434/api/tags
```

## Recommended Models for P100 16GB

| Model            | Size | VRAM (Q4_K_M) | Tool Calling        | Notes                      |
| ---------------- | ---- | ------------- | ------------------- | -------------------------- |
| qwen3:14b        | 14B  | ~9.2 GB       | Excellent (0.97 F1) | Best tool calling accuracy |
| llama3.3:latest  | 8B   | ~5.5 GB       | Good                | Faster, lower quality      |
| deepseek-r1:14b  | 14B  | ~9 GB         | Good                | Strong reasoning           |
| nomic-embed-text | 137M | ~0.3 GB       | N/A                 | Embeddings model           |

With `qwen3:14b` + `nomic-embed-text`, you use about 9.5 GB of the 16 GB VRAM, leaving headroom for context.

## Context Window Tuning

The default config uses `contextWindow: 8192`. You can increase this if your GPU has headroom:

```bash
# On the GPU machine, set Ollama context size
OLLAMA_NUM_CTX=16384 ollama serve
```

Then update `contextWindow` in the OpenClaw config to match.

## Troubleshooting

### Tunnel drops

Use autossh for automatic reconnection:

```bash
autossh -M 0 -f -N -R 11434:localhost:11434 openclaw@your-vps-ip
```

### SearXNG not responding

```bash
systemctl status searxng
journalctl -u searxng -n 50
sudo systemctl restart searxng
```

### Ollama OOM

Reduce context window or switch to a smaller model:

```bash
ollama pull qwen3:8b  # Smaller variant
```

### 400 error: "think value 'low' is not supported"

**Critical fix**: Set `reasoning: false` in your model config. Ollama doesn't support extended thinking modes:

```json
{
  "models": {
    "providers": {
      "ollama": {
        "models": [{
          "reasoning": false  // Must be false for Ollama!
        }]
      }
    }
  }
}
```

The `reasoning` flag tells OpenClaw the model supports Claude/o1-style extended thinking. Ollama doesn't have this API parameter.

### Model not showing in OpenClaw

Check that the explicit provider config in `openclaw.json` has the correct model ID matching what Ollama reports:

```bash
curl http://127.0.0.1:11434/api/tags | python3 -m json.tool
```
