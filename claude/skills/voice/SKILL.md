---
name: voice
description: >-
  Voice synthesis tooling — Piper CLI and Sherpa-ONNX CLI for offline TTS,
  voice model taxonomy (single/multi-speaker, quality tiers), espeak-ng
  phonemization, multi-speaker audition workflows, VITS synthesis parameters,
  Piper training pipeline for custom voices, and voice conversion patterns.
  Use when working with Piper models, TTS configuration, voice preview scripts,
  speaker ID selection, voice model curation, or audio synthesis outside
  the Android context. For Android JNI/AAR Sherpa-ONNX integration, see the
  android skill instead.
---

# Voice Skill

## Piper TTS Overview

Piper is a fast, local neural TTS system using VITS (Variational Inference with adversarial learning for end-to-end Text-to-Speech). Models are exported to ONNX format and run via either the standalone `piper` CLI or the Sherpa-ONNX runtime.

**Two runtimes, same models:**

| Runtime | Use case | Install |
|---------|----------|---------|
| `piper` CLI | Standalone desktop preview, scripting | `piper-tts` in nixpkgs, or build from `OHF-Voice/piper1-gpl` |
| `sherpa-onnx-offline-tts` | Faithful Android-matching preview, multi-model support | Build from `k2-fsa/sherpa-onnx` |

**License note**: `OHF-Voice/piper1-gpl` is GPLv3 — use only for local development, training, and desktop preview. Do not bundle piper1-gpl binaries or code into Android apps or other distributed artifacts. The android skill covers this in detail.

For deck-chat voice work, prefer `piper` CLI for quick audition and `sherpa-onnx-offline-tts` when verifying exact Android behaviour.

## Piper CLI Usage

```bash
# Basic synthesis — text to WAV
echo "Arrr, captain on deck!" | piper --model en_GB-cori-high.onnx --output-file /tmp/sample.wav

# Explicit input text (no pipe)
piper --model en_GB-cori-high.onnx --output-file /tmp/sample.wav --sentence "Hoist the mainsail!"

# Control speech rate (length-scale: <1 faster, >1 slower)
piper --model en_GB-cori-high.onnx --length-scale 0.9 --output-file /tmp/fast.wav

# Multi-speaker model — select speaker by ID
piper --model en_US-libritts-high.onnx --speaker 42 --output-file /tmp/speaker42.wav

# JSON-line mode (batch processing)
echo '{"text": "First line."}' | piper --model model.onnx --output-dir /tmp/batch/ --json-input
```

**Required model files** (must be co-located):
- `<name>.onnx` — the VITS neural network
- `<name>.onnx.json` — config (sample rate, phoneme map, speaker count)

Piper uses espeak-ng for phonemization. The `espeak-ng-data/` directory must be available — either system-installed or bundled with the model archive.

## Sherpa-ONNX CLI Usage

All examples below assume you run from the extracted model directory (e.g., `cd vits-piper-en_GB-cori-high/`), or prefix paths with the model directory.

```bash
# Basic synthesis
sherpa-onnx-offline-tts \
  --vits-model=en_GB-cori-high.onnx \
  --vits-tokens=tokens.txt \
  --vits-data-dir=espeak-ng-data/ \
  --output-filename=/tmp/sample.wav \
  "Arrr, captain on deck!"

# Multi-speaker with speaker ID
sherpa-onnx-offline-tts \
  --vits-model=en_US-libritts-high.onnx \
  --vits-tokens=tokens.txt \
  --vits-data-dir=espeak-ng-data/ \
  --sid=42 \
  --output-filename=/tmp/speaker42.wav \
  "All hands on deck!"

# With speed adjustment (speed: >1 faster, <1 slower — inverse of length_scale)
sherpa-onnx-offline-tts \
  --vits-model=model.onnx \
  --vits-tokens=tokens.txt \
  --vits-data-dir=espeak-ng-data/ \
  --speed=1.2 \
  --output-filename=/tmp/fast.wav \
  "Make way!"
```

**Key difference from Piper CLI**: Sherpa-ONNX requires explicit `--vits-tokens` and `--vits-data-dir` paths. It also uses `--speed` (multiplicative) rather than `--length-scale` (inverse). Internally: `length_scale = 1.0 / speed`.

## Voice Model Taxonomy

### Naming Convention

```
vits-piper-{lang}_{REGION}-{speaker}-{quality}
```

Examples:
- `vits-piper-en_GB-cori-high` — British English, cori speaker, high quality
- `vits-piper-en_US-lessac-medium` — US English, lessac speaker, medium quality
- `vits-piper-en_US-libritts-high` — US English, LibriTTS multi-speaker, high quality

The `vits-piper-` prefix is the Sherpa-ONNX archive naming convention. Piper's own naming omits it: `en_GB-cori-high`.

### Quality Tiers

| Tier | Sample rate | Size | Use case |
|------|-------------|------|----------|
| `x_low` | 16000 Hz | ~15 MB | Constrained devices, testing |
| `low` | 16000 Hz | ~20 MB | Low-bandwidth, acceptable quality |
| `medium` | 22050 Hz | ~40 MB | Training checkpoints, good balance |
| `high` | 22050 Hz | ~80 MB | Production, best single-speaker quality |

**Important**: Only `medium` quality checkpoints are supported for fine-tuning without audio config tweaking. When training custom voices, always start from a medium checkpoint.

### Single vs Multi-Speaker Models

**Single-speaker**: One voice per model. Speaker ID is always 0. Most Piper voices are single-speaker.

**Multi-speaker**: Multiple voices in one model, selected by `--speaker` (Piper) or `--sid` (Sherpa-ONNX). The model's `.onnx.json` config contains `num_speakers` and `speaker_id_map`.

Key multi-speaker models:
- `en_US-libritts-high` — LibriTTS corpus, many English speakers
- `en_US-libritts_r-medium` — LibriTTS-R (improved), medium quality
- `cy_GB-bu_tts-medium` — 7 Welsh speakers
- `es_ES-sharvard-medium` — 2 Spanish speakers

Query speaker count programmatically:
```python
import json
with open("model.onnx.json") as f:
    config = json.load(f)
print(f"Speakers: {config['num_speakers']}")
print(f"Speaker map: {config.get('speaker_id_map', {})}")
```

### Model Sources

| Source | URL | Format |
|--------|-----|--------|
| Piper voices (HuggingFace) | `https://huggingface.co/rhasspy/piper-voices/tree/main` | `.onnx` + `.onnx.json` |
| Sherpa-ONNX releases (GitHub) | `https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/` | `.tar.bz2` archive |
| Piper training checkpoints | `https://huggingface.co/datasets/rhasspy/piper-checkpoints` | `.ckpt` (PyTorch Lightning) |

Sherpa-ONNX archives bundle `.onnx` + `tokens.txt` + `espeak-ng-data/` — ready to use without system espeak-ng.

## VITS Synthesis Parameters

| Parameter | Default | Effect |
|-----------|---------|--------|
| `noise_scale` | 0.667 | Stochasticity in pronunciation. Higher = more variation between generations. Lower = more deterministic. |
| `noise_scale_w` | 0.8 | Stochasticity in duration prediction. Higher = more timing variation. |
| `length_scale` | 1.0 | Speech rate. `< 1.0` = faster, `> 1.0` = slower. `0.8` is 20% faster. |

These are set in the Piper CLI via `--noise-scale`, `--noise-w`, `--length-scale`. In Sherpa-ONNX, `--vits-noise-scale`, `--vits-noise-scale-w`, and `--speed` (where `speed = 1.0 / length_scale`).

For voice audition, keep defaults. Adjust `length_scale` for pacing tests. Leave `noise_scale` / `noise_scale_w` alone unless experimenting with speech naturalness.

## Multi-Speaker Audition Workflow

When evaluating multi-speaker models for crew voice assignment:

```bash
# 1. Download the multi-speaker model
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-libritts-high.tar.bz2
tar xjf vits-piper-en_US-libritts-high.tar.bz2

# 2. Define model directory and check how many speakers are available
MODEL_DIR="vits-piper-en_US-libritts-high"
NUM_SPEAKERS=$(python3 -c "import json; c=json.load(open('$MODEL_DIR/en_US-libritts-high.onnx.json')); print(c['num_speakers'])")
echo "$NUM_SPEAKERS speakers available"

# 3. Batch-generate samples across speaker IDs (first 50 or all if fewer)
MAX_SID=$(( NUM_SPEAKERS < 50 ? NUM_SPEAKERS - 1 : 49 ))
TEXT="Arrr, all hands on deck! The storm approaches from the east."
mkdir -p /tmp/audition
for sid in $(seq 0 "$MAX_SID"); do
  piper --model "$MODEL_DIR/en_US-libritts-high.onnx" \
    --speaker "$sid" \
    --output-file "/tmp/audition/speaker-${sid}.wav"  <<< "$TEXT"
done

# 4. Listen and rate — look for gravel, depth, authority, clarity
# Linux: aplay, mpv | macOS: afplay | or any audio player
for f in /tmp/audition/speaker-*.wav; do
  echo "Playing: $f"
  mpv --no-video "$f" 2>/dev/null || aplay "$f" 2>/dev/null || afplay "$f"
  read -p "Rate (1-5, or s to skip): " rating
done
```

**Rating criteria for pirate voices:**
- **Gravel**: Rough, textured quality — sounds weathered
- **Depth**: Low pitch, resonant — carries across decks
- **Authority**: Commanding presence — sounds like they give orders
- **Clarity**: Intelligible despite character — words don't get lost
- **Distinctiveness**: Sounds different from other crew — immediately identifiable

## Voice Preview in devenv

When adding voice preview to a Nix devenv (e.g., deck-chat):

```nix
# devenv.nix — add piper-tts to packages
packages = [
  pkgs.piper-tts
  # ... existing packages
];

# Add a preview-voice convenience script
scripts.preview-voice.exec = ''
  set -euo pipefail
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  TTS_DIR="$REPO_ROOT/app/src/main/assets/tts"

  usage() {
    echo "Usage: preview-voice <crew-name> \"text to speak\""
    echo "       preview-voice --list"
    echo "       preview-voice --model <dir> [--speaker-id N] \"text\""
    exit 1
  }

  # ... argument parsing, crew-to-model mapping, piper invocation
'';
```

The preview script should:
- Map crew names to model directories (matching `CrewRegistry.kt`)
- Support `--list` to show available voices
- Support `--model <dir>` for auditioning arbitrary models
- Support `--speaker-id N` for multi-speaker models
- Output WAV to stdout (pipeable) or `--output <path>`
- Play audio directly if `aplay` or `mpv` is available

## Piper Training Pipeline

For training custom voices from audio datasets.

### Prerequisites

```bash
git clone https://github.com/OHF-Voice/piper1-gpl.git
cd piper1-gpl
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -e '.[train]'
./build_monotonic_align.sh
```

System packages: `build-essential`, `cmake`, `ninja-build`.

### Training Data Format

**Single-speaker** — CSV with `|` delimiter:
```csv
utt1.wav|Text for utterance one.
utt2.wav|Text for utterance two.
```

**Multi-speaker** — add speaker name column:
```csv
utt1.wav|bosun|Haul the anchor, ye dogs!
utt2.wav|lookout|Ship on the horizon, bearing north-northeast.
```

Speaker names are mapped to IDs automatically during training. The mapping is saved in the output `config.json`.

Audio files can be any format supported by librosa (WAV preferred). Place them in a single directory.

### Training Command

```bash
python3 -m piper.train fit \
  --data.voice_name "pirate-bosun" \
  --data.csv_path /path/to/metadata.csv \
  --data.audio_dir /path/to/audio/ \
  --model.sample_rate 22050 \
  --data.espeak_voice "en-us" \
  --data.cache_dir /path/to/cache/ \
  --data.config_path /path/to/config.json \
  --data.batch_size 32 \
  --ckpt_path /path/to/medium-checkpoint.ckpt
```

**Always use `--ckpt_path`** with a medium quality pretrained checkpoint — dramatically speeds up training, even cross-language. Download checkpoints from `https://huggingface.co/datasets/rhasspy/piper-checkpoints`.

### ONNX Export

```bash
python3 -m piper.train.export_onnx \
  --checkpoint /path/to/best-checkpoint.ckpt \
  --output-file en_US-pirate-bosun-medium.onnx
```

Name the ONNX file as `{lang}_{REGION}-{name}-{quality}.onnx`. The training config JSON gets the same name with `.json` extension:
- `en_US-pirate-bosun-medium.onnx`
- `en_US-pirate-bosun-medium.onnx.json`

### Hardware Requirements

Reference (from upstream Piper training):
- NVIDIA A6000 (48 GB VRAM) or 3090 (24 GB VRAM)
- Users report success with as little as 8 GB VRAM (e.g., RX 7600)
- CPU: Threadripper-class with 128 GB RAM (reference), but consumer hardware works for fine-tuning
- Fine-tuning from checkpoint: hours to days depending on dataset size and GPU

### Data Requirements

| Approach | Audio needed | Quality | Training time |
|----------|-------------|---------|---------------|
| Fine-tune from checkpoint | ~30 min | Good (transfers base voice character) | Hours |
| Full training | 1-2 hours | Best (fully custom) | Days |
| Vocoder warmstart | 1-2 hours | Good (fresh phoneme embedding) | Days (faster than scratch) |

Use `--model.vocoder_warmstart_ckpt` when training from scratch with a different phoneme set — it copies vocoder weights without the phoneme embedding layer.

## Voice Conversion (Post-Synthesis)

Voice conversion applies style/timbre changes to already-synthesized speech. Pipeline: Piper generates clean audio → conversion model adds character.

### Tools

| Tool | Approach | Reference audio needed | On-device feasible |
|------|----------|----------------------|-------------------|
| OpenVoice | Zero-shot tone cloning | ~10 seconds | No (GPU inference) |
| RVC | Retrieval-based conversion | ~10 min training data | No (GPU inference) |
| so-vits-svc | Singing voice conversion | ~30 min training data | No (GPU inference) |

**None of these are feasible for on-device Android runtime.** Use as:
- **Build-time pipeline**: Pre-generate crew responses with conversion applied, ship as audio assets
- **Server-side**: If latency budget allows, run conversion on a server (adds network dependency, breaks offline-first)
- **Training data augmentation**: Convert reference audio to create more training data for Piper fine-tuning

### Architecture Decision

For an offline-first Android app, voice conversion is best used as a **development tool** (exploring voice characteristics) or **training data augmentation** (creating varied training samples), not as a runtime component. Invest in Piper fine-tuning (Tier 3) for production pirate voices.

## Anti-Patterns

- **Using cloud TTS for an offline-first app** — defeats the purpose. On-device Android runtime is via Sherpa-ONNX; Piper CLI is for local desktop preview and training only (GPLv3, not distributable).
- **Shipping voices without desktop audition** — always preview with `piper` CLI before committing to a voice profile. Building the APK to test a voice is a 5-minute tax per iteration.
- **Skipping the `.onnx.json` config file** — Piper requires it alongside the `.onnx` model. Sherpa-ONNX archives bundle `tokens.txt` + `espeak-ng-data/` instead.
- **Using `high` checkpoints for fine-tuning** — only `medium` quality checkpoints are supported without audio config tweaking. Always fine-tune from medium.
- **Ignoring speaker count in multi-speaker models** — always check `num_speakers` in the config before generating. Speaker IDs outside the valid range cause silent failure or garbage output.
- **Hardcoding speaker IDs without audition** — systematically evaluate candidates. A speaker that sounds good on one phrase may not generalise.
- **Confusing `speed` and `length_scale`** — they are inverses. `speed=2.0` in Sherpa-ONNX equals `length_scale=0.5` in Piper. Mixing them up doubles or halves speech rate unexpectedly.
- **Training on noisy audio** — Piper VITS is sensitive to recording quality. Clean, consistent audio with minimal background noise produces far better results.
- **Assuming voice conversion runs on-device** — current tools (OpenVoice, RVC) require GPU inference. Plan for build-time or server-side processing only.
- **Over-pirating text transforms** — a few "arrr"s and "ye"s add flavour; every sentence ending in "shiver me timbers" becomes grating fast. Less is more.
