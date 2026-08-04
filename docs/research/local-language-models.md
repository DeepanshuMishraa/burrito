# Downloadable local language models

**Research date:** August 4, 2026

## Recommendation

Keep Apple Foundation Models as the zero-download default. Offer one optional Qwen3.5 model at each quality tier, using 4-bit MLX runtime bundles and a native Swift runtime:

| Tier | Model | Proposed quantization | Download target | Practical Mac target |
| --- | --- | --- | --- | --- |
| Small | **Qwen3.5-2B** | 4-bit MLX | about **1.75 GB** | 8 GB unified memory |
| Medium | **Qwen3.5-4B** | 4-bit MLX | about **3.06 GB** | 16 GB unified memory |
| Large | **Qwen3.5-9B** | 4-bit MLX | about **5.98 GB** | 24 GB recommended; 16 GB only with a conservative context limit |

These figures match current MLX Community 4-bit conversions, not first-party Qwen artifacts: [2B is 1.75 GB](https://huggingface.co/mlx-community/Qwen3.5-2B-4bit/tree/main), [4B is 3.06 GB](https://huggingface.co/mlx-community/Qwen3.5-4B-4bit/tree/main), and [9B is 5.98 GB](https://huggingface.co/mlx-community/Qwen3.5-9B-4bit/tree/main). Burrito should produce and benchmark deterministic conversions from pinned Qwen checkpoints, package only the files required for text generation, and record the resulting sizes before the UI promises a number.

Qwen3.5 is the best quality-first candidate found within these size bands. The official 4B/9B model card reports MMLU-Pro scores of 79.1/82.5, GPQA Diamond 76.2/81.7, IFEval 89.8/91.5, and multilingual MMLU 76.1/81.2. The 2B card reports 66.5 MMLU-Pro in thinking mode, versus 56.5 for the older Qwen3-1.7B. Vendor-run benchmarks are useful selection evidence, not proof of Burrito note quality. [Qwen3.5 2B model card](https://huggingface.co/Qwen/Qwen3.5-2B), [Qwen3.5 4B model card](https://huggingface.co/Qwen/Qwen3.5-4B), [Qwen3.5 9B model card](https://huggingface.co/Qwen/Qwen3.5-9B)

All three checkpoints are Apache-2.0. Burrito may redistribute quantized derivatives if the distribution preserves the license and required notices, marks modifications, and does not imply trademark permission. Ship the model license and provenance beside every downloaded artifact. [Qwen3.5 4B license metadata](https://huggingface.co/Qwen/Qwen3.5-4B), [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)

## Why this family

- **Capability:** Qwen's own results put the 4B and 9B models near or above much larger older open-weight models across knowledge, reasoning, instruction following, long context, and multilingual tests. The 9B tier is a meaningful upgrade, rather than merely a slower version of the same quality.
- **One integration contract:** all tiers share the tokenizer, chat template, thinking behavior, license, and runtime architecture. This reduces three-model product support to one family with three weight bundles.
- **Useful language coverage:** Qwen states support for 201 languages and dialects. Burrito should still benchmark the languages it advertises; broad training coverage is not a quality guarantee. [Qwen3.5 9B model card](https://huggingface.co/Qwen/Qwen3.5-9B)
- **Long input without forcing long runtime context:** the models advertise a native 262,144-token context, but Burrito should initially cap local inference at 16K tokens and retain its existing digest/chunking pipeline. Maximum context would consume needless memory for meeting-note generation. [Qwen3.5 4B model card](https://huggingface.co/Qwen/Qwen3.5-4B)
- **Redistribution:** Apache-2.0 is materially simpler for an open-source app than gated weights or a model-specific community license.

The principal risk is recency. Qwen3.5 support only landed in MLX Swift LM 2.31.3, including text-only and vision implementations, Qwen3.5-specific performance work, and tool-call fixes. Treat the family as a release candidate until it passes Burrito's own stability and quality suite. [MLX Swift LM 2.31.3 release](https://github.com/ml-explore/mlx-swift-lm/releases/tag/2.31.3)

## Runtime choice

### Primary: MLX Swift LM

Use `mlx-swift-lm` in-process and run Qwen3.5 through its text-only model path. Apple describes MLX as designed for Apple silicon, with a Swift API and shared CPU/GPU memory rather than copies between devices. MLX Swift LM supplies native model loading/generation and explicit Qwen3.5 text support, so Burrito does not need Python or a local server at runtime. Both projects use MIT licenses. [MLX](https://github.com/ml-explore/mlx), [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm), [Qwen3.5 support release](https://github.com/ml-explore/mlx-swift-lm/releases/tag/2.31.3)

Build the downloadable bundles from pinned upstream revisions and a pinned conversion toolchain. Each manifest should contain the source revision, quantization recipe, tokenizer/config files, file sizes, SHA-256 hashes, model and runtime licenses, minimum Burrito/runtime version, and a rollback version. Burrito should download into a staging directory, verify every hash and expected byte count, then atomically install it. Interrupted or corrupt downloads must leave the existing model intact.

### Fallback: llama.cpp with GGUF

Keep a prototype backend for `llama.cpp`. It has a Metal backend, a stable C API, single-file GGUF distribution, and broad tooling. It is also the safest way to ship the older fallback models below because their publishers provide official GGUF files. The tradeoff is a C/C++ bridge and a second inference stack. Do not select the backend from generic tokens-per-second claims; compare the exact Burrito prompts and quantizations on supported Macs. [llama.cpp repository](https://github.com/ggml-org/llama.cpp), [Metal build option](https://github.com/ggml-org/llama.cpp/blob/master/ggml/CMakeLists.txt)

### Do not lead with Core ML

Core ML is attractive for a fully Apple-native stack, but there are no first-party Core ML packages for the recommended Qwen3.5 variants. Burrito would own model conversion, operator compatibility, state/cache behavior, and large compiled assets. MLX Swift already targets the supported Apple-silicon-only platform and has explicit implementations for these models. Reconsider Core ML only if a controlled prototype beats MLX materially on energy, time to first token, and sustained generation while matching output quality.

## Memory expectations

Download size is not peak memory. Resident weights are joined by runtime allocations, temporary compute buffers, tokenizer state, generation state/cache, prompt tokens, and the rest of Burrito. Apple silicon shares that memory with the GPU and the entire system.

Use these as product gates until measured:

| Tier | Expected incremental peak | Product rule |
| --- | --- | --- |
| Small | roughly **3–4.5 GB** | Allow on 8 GB Macs, but warn/stop cleanly under memory pressure. |
| Medium | roughly **5–7 GB** | Require 16 GB unified memory. |
| Large | roughly **9–12 GB** | Recommend 24 GB; on 16 GB require 8K–16K context and prevent concurrent local models. Hide it on 8 GB. |

These are conservative planning ranges, not measurements. `llama.cpp` recommends keeping model workloads below roughly 70% of unified memory on Apple silicon; Burrito should be stricter because transcription, the UI, and other applications remain active. [llama.cpp Apple-silicon memory guidance](https://github.com/ggml-org/llama.cpp/discussions/15396)

Only one LLM should be loaded at once. Unload it after generation or after a short idle window. Never keep an ASR model and the large LLM resident concurrently unless benchmarks prove the supported memory tier can sustain both. Surface installed disk size separately from estimated run-time memory.

## Sensible alternatives

### Small tier

- **Qwen3-1.7B Q8_0 — safest launch fallback.** Qwen publishes an Apache-2.0 GGUF artifact at exactly 1.83 GB. It is older and materially weaker than Qwen3.5-2B on Qwen's reported tests, but it removes Burrito-owned conversion from the first implementation. [Official Qwen3-1.7B GGUF](https://huggingface.co/Qwen/Qwen3-1.7B-GGUF)
- **Ministral 3 3B Q4_K_M — size-edge alternative.** Mistral publishes an Apache-2.0 GGUF at 2.15 GB and explicitly designs the family for edge deployment. It narrowly misses the requested 2 GB ceiling, so it should not be the primary small SKU. [Official Ministral 3 3B GGUF](https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512-GGUF)

### Medium tier

- **Ministral 3 3B Q8_0 — safest launch fallback.** The official Apache-2.0 GGUF is 3.65 GB, exactly in the target band, and is instruction-tuned for local use. It has a smaller language model than Qwen3.5-4B and supports fewer named languages, but its artifact and llama.cpp path are ready-made. [Official Ministral 3 3B GGUF](https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512-GGUF)
- **Qwen3-4B Q6_K — mature same-family fallback.** A Q6 conversion is approximately 3.3 GB; Qwen publishes official Apache-2.0 GGUF variants, although its official repository should be checked for the exact chosen file before release. Qwen3 is older and its official evaluations trail Qwen3.5 substantially. [Official Qwen3-4B GGUF](https://huggingface.co/Qwen/Qwen3-4B-GGUF)

### Large tier

- **Ministral 3 8B Q5_K_M — safest launch fallback.** Mistral publishes an Apache-2.0 GGUF at 6.06 GB, directly matching the requested tier. Q4_K_M is 5.2 GB if memory pressure matters more than quality. [Official Ministral 3 8B GGUF files](https://huggingface.co/mistralai/Ministral-3-8B-Instruct-2512-GGUF/tree/main)
- **Qwen3-8B Q5_K_M — mature same-family fallback.** Qwen's official Apache-2.0 file is 5.85 GB. It supports 100+ languages, thinking/non-thinking modes, and a native 32K context. [Official Qwen3-8B GGUF](https://huggingface.co/Qwen/Qwen3-8B-GGUF), [Q5_K_M file](https://huggingface.co/Qwen/Qwen3-8B-GGUF/blob/main/Qwen3-8B-Q5_K_M.gguf)

Gemma 3 remains technically credible, especially Google's QAT GGUF releases, but its gated acceptance flow and Gemma-specific terms add avoidable download and redistribution friction. Llama models likewise introduce a custom community license. Neither beats an Apache-2.0 option clearly enough for Burrito's first three downloads. [Gemma 3 QAT GGUF](https://huggingface.co/google/gemma-3-4b-it-qat-q4_0-gguf), [Gemma terms](https://ai.google.dev/gemma/terms), [Llama 3.2 license](https://www.llama.com/llama3_2/license/)

## Execution plan

1. **Freeze the evaluation contract.** Extract 50–100 representative Burrito inputs: short and long transcripts, noisy transcripts, multilingual meetings, user notes, templates, title generation, digest merging, citation-heavy final notes, and insufficient-evidence memory questions. Remove private data or create equivalent fixtures.
2. **Define release gates before comparing models.** Score factuality, unsupported claims, citation validity, required Markdown structure, title quality, instruction following, language fidelity, refusals, repetition, and truncation. Add human pairwise review for usefulness. A leaderboard score alone must not choose the model.
3. **Build pinned MLX artifacts for text generation.** Convert Qwen3.5 2B/4B/9B at 4 bits, package only runtime-required files, record exact sizes and hashes, and retain BF16 outputs for quantization comparison. Also benchmark 6-bit versions to quantify how much quality the smaller downloads trade away. Include Apache license/provenance in every bundle. Do not depend on mutable community conversions in production.
4. **Build a disposable native harness.** Exercise the existing `PromptTokenMeasuring` and `TextCompleting` behavior through MLX Swift LM without changing the production generator. Validate cancellation, deterministic shutdown, repeated load/unload, malformed bundles, and memory-pressure recovery.
5. **Benchmark the support matrix.** At minimum test the oldest 8 GB Apple-silicon Mac, a 16 GB baseline, and a 24/32 GB machine. Record download/install time, cold load, prompt processing, time to first token, output tokens/second, end-to-end note time, peak and sustained memory, swap, thermal throttling, and energy impact at 8K and 16K contexts.
6. **Run quality A/B tests.** Compare Apple Foundation Models, each Qwen3.5 tier, and the safer GGUF alternative for that tier. Compare quantized output to BF16. Reject any tier that does not produce a material user-visible gain over the tier below it.
7. **Choose MLX or GGUF from evidence.** Prefer MLX if it is stable and competitive because the integration remains native Swift. Fall back to llama.cpp plus the official Qwen3/Ministral artifacts if Qwen3.5 conversion, memory, or runtime stability misses the gates.
8. **Design model lifecycle before UI.** Extend the existing Models tab concept with resumable download, progress, required disk space, run-time memory recommendation, checksum verification, versioning, delete/retry, active-model selection, and an automatic fallback to Apple when a local model is absent or fails to load.
9. **Ship one tier first.** Release the small model behind an experimental setting, collect opt-in local diagnostics that contain no transcript text, then medium, then large. This isolates runtime and artifact problems before users download 6 GB.
10. **Re-evaluate periodically.** Model quality changes quickly. Keep the runtime interface and manifest family-neutral, but do not expose arbitrary user models in the first release; that expands support and security scope substantially.

## Release decision

The quality-first destination is **Qwen3.5 2B / 4B / 9B through MLX Swift**, packaged by Burrito at approximately 1.75 / 3.06 / 5.98 GB. The low-risk fallback is **official GGUF through llama.cpp**: Qwen3-1.7B Q8 (1.83 GB), Ministral 3 3B Q8 (3.65 GB), and either Qwen3-8B Q5 (5.85 GB) or Ministral 3 8B Q5 (6.06 GB).

Do not promise the Qwen3.5 download sizes or supported-memory labels until the pinned conversions and Burrito-specific benchmarks produce measured numbers. Do not replace Apple as the default: the system model remains the instant, zero-storage, lowest-pressure option, while downloaded models are explicit quality upgrades.
