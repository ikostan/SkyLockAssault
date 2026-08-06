# 📊 Local AI Models Summary Matrix (v3.2)

**Target Hardware:** Intel Core Ultra 9 285H | NVIDIA RTX 5060 Ti (16 GB GDDR7 VRAM) | 32 GB System RAM
**Primary Stack:** Godot v4.x (GDScript), Python (Playwright), GUT/GDUnit4, ComfyUI
**Last Updated:** August 2026 | Validated against Ollama library releases

> **Why these models?** This guide prioritizes local inference on a 16 GB VRAM GPU with 32 GB system RAM rather than chasing raw benchmark scores. Models were selected based on code generation quality, reasoning ability, inference speed, VRAM efficiency, and direct suitability for Godot 4, Python Playwright, and game development workflows.

---

## 🌳 Quick Start Decision Tree

```text
Need sub-second inline autocomplete?
 └── 🚀 Qwen3.6 8B (Q8_0)

Need daily GDScript 4, GUT testing, or Playwright Python?
 └── ⭐ Qwen2.5-Coder 14B (Q5_K_M)

Need visual UI screenshot debugging or visual GDD analysis?
 └── 🖼️ Gemma 4 12B (Q5_K_M)

Need step-by-step game AI state machines & math verification?
 └── 🧠 Phi-4-Reasoning 14B or DeepSeek-R1 Distill 14B (Q4_K_M)

Need an all-in-one coding + planning model (Apache 2.0)?
 └── 🛠️ OpenAI gpt-oss-20b (Q4_K_M)

Need agentic multi-file repository issue solving?
 └── 🤖 Devstral Small 2 (24B) (Q5_K_M)

Need deep multi-file codebase refactoring without breaking logic?
 └── 🌙 Qwen2.5-Coder 32B (Q4_K_M) [Recommended Overnight Refactoring Model]

```

---

## 📦 Suggested Installation Order

To get up and running without downloading hundreds of gigabytes at once, install models in this recommended sequence:

1. `ollama run qwen2.5-coder:14b` *(Primary GDScript 4, GUT & Playwright Coder)*
2. `ollama run gemma4:12b` *(Primary Multimodal UI Screenshot Analyzer)*
3. `ollama run gpt-oss:20b` *(Primary All-in-One Reasoning & Coding MoE)*
4. `ollama run phi4-reasoning` *(Primary Step-by-Step Logic & Math Verifier)*
5. `ollama run devstral-small-2:24b` *(Primary Agentic Multi-File Repository Editor)*
6. `ollama run qwen2.5-coder:32b` *(Recommended Overnight Multi-File Refactoring Engine)*

> 💡 **Pro-Tips for Local Tuning:**
> * **Performance Benchmark:** Run `ollama run <model> --verbose` with a short prompt to verify your token generation rate (`eval rate` in t/s).
> * **KV-Cache Optimization:** Set `OLLAMA_KV_CACHE_TYPE=q4_0` as a system environment variable to compress the KV cache, freeing up 2–4 GB of additional VRAM for ultra-long context windows on 14B models.

---

## 💾 Hardware Memory Fit & System RAM Allocation

| Memory Pool                    | Model Class                     | Execution Profile                                                       | System RAM Headroom (32 GB Total)             | Usability Rating                 |
|--------------------------------|---------------------------------|-------------------------------------------------------------------------|-----------------------------------------------|----------------------------------|
| **16 GB VRAM (100% GPU)**      | **4B–14B Dense** & **20B MoE**  | Zero RAM offload, Max speed (`Ultra` / `Fast`), large KV cache headroom | **~18–22 GB Free** (OS + Godot + Playwright)  | ✅ **Optimal Daily Driver**      |
| **16 GB VRAM + ~2–5 GB RAM**   | **22B–27B Dense** & **35B MoE** | Light RAM spill, High speed (`Medium`), minor context impact            | **~12–15 GB Free** (Fluid multitasking)       | 🟡 **Active Choice**             |
| **16 GB VRAM + ~6–10 GB RAM**  | **32B Dense**                   | Moderate RAM spill, Reduced speed (`Heavy`), tighter KV headroom        | **~8–10 GB Free** (Dedicated coding sessions) | 🟠 **Overnight / Deep Refactor** |
| **16 GB VRAM + ~15–20 GB RAM** | **49B–72B Heavy**               | Heavy RAM spill, Low speed (`Slow`), high System RAM pressure           | **~3–6 GB Free** (Background tasks only)      | 🔴 **Occasional Deep Planning**  |

---

## ⚡ Category 1: Ultra-Fast Autocomplete & Inline Drafting (60–100+ t/s)

*Note: All recommended models support ~128K context windows in current Ollama releases.*

| Model Name       | Rank                  | Best For                      | Speed | License     | Quant  | Recommended Ollama Command |
|------------------|-----------------------|-------------------------------|-------|-------------|--------|----------------------------|
| **Qwen3.6 8B**   | ⭐ Primary            | GDScript FIM autocomplete     | Ultra | Apache 2.0  | `Q8_0` | `ollama run qwen3.6:8b`    |
| **Llama 3.1 8B** | Excellent Alternative | Commit logs & Markdown        | Ultra | Llama Comm. | `Q8_0` | `ollama run llama3.1:8b`   |
| **Gemma 4 4B**   | Specialized           | UI layout & screenshot checks | Ultra | Gemma       | `Q8_0` | `ollama run gemma4:4b`     |

---

## 💻 Category 2A: 100% VRAM "Daily Drivers" — Coding & Testing (35–60 t/s)

These models fit completely inside 16 GB VRAM, maintaining max generation speed and full context headroom for active development.

| Model Name               | Rank                  | Best For                                | Speed | License    | Quant    | Recommended Ollama Command     |
|--------------------------|-----------------------|-----------------------------------------|-------|------------|----------|--------------------------------|
| **Qwen2.5-Coder 14B**    | ⭐ Primary            | GDScript 4, GUT, Playwright             | Fast  | Apache 2.0 | `Q5_K_M` | `ollama run qwen2.5-coder:14b` |
| **Qwen3.6 14B / Coder**  | Excellent Alternative | Modern GDScript 4 & agentic completion  | Fast  | Apache 2.0 | `Q5_K_M` | `ollama run qwen3.6:14b`       |
| **IBM Granite Code 20B** | Specialized           | Enterprise C++ & Python (Short context) | Fast  | Apache 2.0 | `Q5_K_M` | `ollama run granite-code:20b`  |

---

## 🧠 Category 2B: 100% VRAM "Daily Drivers" — Reasoning & Multimodal (35–60 t/s)

| Model Name                  | Rank        | Best For                       | Speed | License    | Quant    | Recommended Ollama Command   |
|-----------------------------|-------------|--------------------------------|-------|------------|----------|------------------------------|
| **OpenAI gpt-oss-20b**      | ⭐ Primary  | General reasoning & coding     | Fast  | Apache 2.0 | `Q4_K_M` | `ollama run gpt-oss:20b`     |
| **Gemma 4 12B**             | ⭐ Primary  | UI screenshots & visual GDD    | Fast  | Gemma      | `Q5_K_M` | `ollama run gemma4:12b`      |
| **Phi-4-Reasoning (14B)**   | ⭐ Primary  | Logic, state machines & math   | Fast  | MIT        | `Q4_K_M` | `ollama run phi4-reasoning`  |
| **DeepSeek-R1 Distill 14B** | Specialized | Logic & collision verification | Fast  | MIT        | `Q4_K_M` | `ollama run deepseek-r1:14b` |
| **Microsoft Phi-4 (14B)**   | Specialized | Collision geometry & math      | Fast  | MIT        | `Q5_K_M` | `ollama run phi4`            |

---

## 🌤️ Category 3A: Light-Offload Models — Coding & Agentic (20–35 t/s)

These models spill 2–5 GB into System RAM, maintaining high generation speeds while delivering 20B–35B parameter capability.

| Model Name                 | Rank                  | Best For                              | Speed  | License    | Quant    | Recommended Ollama Command             |
|----------------------------|-----------------------|---------------------------------------|--------|------------|----------|----------------------------------------|
| **Devstral Small 2 (24B)** | ⭐ Primary            | Agentic multi-file repository editing | Medium | Apache 2.0 | `Q5_K_M` | `ollama run devstral-small-2:24b`      |
| **Mistral-Small 3 (24B)**  | Excellent Alternative | Polyglot code refactoring             | Medium | Apache 2.0 | `Q5_K_M` | `ollama run mistral-small:24b`         |
| **Codestral 22B**          | Specialized           | FIM completion & polyglot             | Medium | Apache 2.0 | `Q5_K_M` | `ollama run codestral:22b-v0.1-q5_K_M` |

---

## 🌤️ Category 3B: Light-Offload Models — Architecture, Lore & GDD (20–35 t/s)

| Model Name          | Rank                  | Best For                         | Speed  | License    | Quant    | Recommended Ollama Command   |
|---------------------|-----------------------|----------------------------------|--------|------------|----------|------------------------------|
| **Qwen3.6 35B-A3B** | ⭐ Primary            | Fast MoE planning                | Medium | Apache 2.0 | `Q4_K_M` | `ollama run qwen3.6:35b-a3b` |
| **Gemma 4 27B**     | ⭐ Primary            | Documentation & GDD              | Medium | Gemma      | `Q4_K_M` | `ollama run gemma4:27b`      |
| **Qwen3-30B-A3B**   | Excellent Alternative | MoE assistant & structured specs | Medium | Apache 2.0 | `Q4_K_M` | `ollama run qwen3:30b-a3b`   |

---

## 🐘 Category 4: Heavy-Offload Models — Deep Planning & Overnight Refactoring (4–18 t/s)

These models offload 6–20 GB into System RAM. Generation is slower, but parameter depth prevents regressions during multi-file code repair.

| Model Name                   | Rank              | Best For                      | Speed | License     | Quant    | Recommended Ollama Command                |
|------------------------------|-------------------|-------------------------------|-------|-------------|----------|-------------------------------------------|
| **Qwen2.5-Coder 32B**        | 🌙 Overnight      | Overnight GDScript 4 repair   | Heavy | Apache 2.0  | `Q4_K_M` | `ollama run qwen2.5-coder:32b`            |
| **DeepSeek V4 Distill 32B**  | Specialized       | Collision planning & AI logic | Heavy | Apache 2.0  | `Q4_K_M` | `ollama run deepseek-v4:32b`              |
| **Qwen3-32B**                | Specialized       | Dual-reasoning planning       | Heavy | Apache 2.0  | `Q4_K_M` | `ollama run qwen3:32b`                    |
| **Llama Nemotron Super 49B** | Heavy Alternative | Full-codebase ingestion       | Slow  | Llama Comm. | `IQ3_M`  | `ollama run nemotron-super:49b`           |
| **Llama 3.3 70B Instruct**   | Heavy Alternative | GDD & documentation           | Slow  | Llama Comm. | `IQ3_M`  | `ollama run llama3.3:70b-instruct-q3_K_M` |
| **Qwen2.5 72B Instruct**     | Heavy Alternative | Polyglot architecture         | Slow  | Apache 2.0  | `Q3_K_L` | `ollama run qwen2.5:72b-instruct-q3_K_L`  |

> 📌 **Note on GLM-4.5-Air & Kimi K2:** While outstanding models, GLM-4.5-Air (~73GB GGUF) and Kimi K2 (1T+ MoE) exceed local consumer 32 GB System RAM limits for usable throughput. They are best accessed via cloud API endpoints or specialized multi-GPU host instances.

---

## 🎨 Category 5: Image & 3D Asset Generation (ComfyUI)

Non-LLM models running directly inside GPU VRAM for 2D textures, UI sprites, and 3D mesh workflows. Keep workflows single-image or carefully batched to stay under 16 GB VRAM.

| Model Name                  | Rank        | Best For                                           | Environment     | Speed / Render Time    |
|-----------------------------|-------------|----------------------------------------------------|-----------------|------------------------|
| **FLUX.1 Schnell (fp8)**    | ⭐ Primary  | 2D game concept art, UI textures & sprite bases    | ComfyUI / Forge | ~4–8 sec (1024x1024)   |
| **SDXL Turbo / Lightning**  | ⭐ Primary  | Fast sprite sheets, UI icons & rapid texture loops | ComfyUI         | ~1–3 sec (1024x1024)   |
| **FLUX.1 Dev (fp8 / GGUF)** | Specialized | High-detail concept art & textured 3D mesh bases   | ComfyUI         | ~10–18 sec (1024x1024) |

---

## ⚙️ Disclaimer & Technical Notes

1. **VRAM & Throughput Variations:** Estimated generation speeds (`Ultra`: 60–100+ t/s, `Fast`: 35–60 t/s, `Medium`: 20–35 t/s, `Heavy`: 4–18 t/s, `Slow`: <5 t/s) and VRAM allocations are approximate. Actual metrics depend on the inference backend (Ollama, llama.cpp, vLLM), context length prefill overhead, KV cache quantization setting (e.g., `q4_0` vs `fp16` KV cache), and concurrent system background tasks.
2. **Quantization Guideline:** `Q4_K_M` and `Q5_K_M` represent the sweet spot for 14B–32B models on 16 GB VRAM. Use `Q8_0` primarily for sub-10B models where VRAM headroom is abundant.
3. **GDDR7 Bandwidth Advantage:** The RTX 5060 Ti's higher memory bandwidth significantly speeds up token evaluation and generation for sub-20B models compared to previous-generation 16 GB cards.
