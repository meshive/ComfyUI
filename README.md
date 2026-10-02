[![Build and Push Docker Images](https://github.com/somb1/ComfyUI-Docker/actions/workflows/build.yml/badge.svg)](https://github.com/somb1/ComfyUI-Docker/actions/workflows/build.yml)

> 🔄 **Built on demand** — images are published by a manual `docker buildx bake` run.

> 💬 Feedback & Issues → [GitHub Issues](https://github.com/somb1/ComfyUI-Docker/issues)

> 🚀 This Docker image was originally built for running on RunPod, but it can also be used on your local machine. See the [Local Setup Guide(WiP)](https://github.com/somb1/ComfyUI-Docker/wiki/Running-on-Local).

## 🔌 Exposed Ports

| Port | Type | Service     |
| ---- | ---- | ----------- |
| 22   | TCP  | SSH         |
| 3000 | HTTP | ComfyUI     |
| 8080 | HTTP | code-server |
| 8888 | HTTP | JupyterLab  |

---

## 🏷️ Tag Format

```text
sombi/comfyui:(A)-torch2.8.0-(B)
```

* **(A)**: `slim` or `base`
  * `slim`: ComfyUI + Manager only
  * `base`: slim + pre-installed custom nodes
* **(B)**: CUDA version → `cu124`, `cu126`, `cu128`

---

## 🧱 Image Variants

| Image Name                            | Custom Nodes | CUDA |
| ------------------------------------- | ------------ | ---- |
| `sombi/comfyui:base-torch2.8.0-cu124` | ✅ Yes        | 12.4 |
| `sombi/comfyui:base-torch2.8.0-cu126` | ✅ Yes        | 12.6 |
| `sombi/comfyui:base-torch2.8.0-cu128` | ✅ Yes        | 12.8 |
| `sombi/comfyui:slim-torch2.8.0-cu124` | ❌ No         | 12.4 |
| `sombi/comfyui:slim-torch2.8.0-cu126` | ❌ No         | 12.6 |
| `sombi/comfyui:slim-torch2.8.0-cu128` | ❌ No         | 12.8 |

> 👉 To switch: **Edit Pod/Template** → set `Container Image`.

---

## ⚙️ Environment Variables

| Variable                | Description                                                                | Default   |
| ----------------------- | -------------------------------------------------------------------------- | --------- |
| `ACCESS_PASSWORD`       | Password for JupyterLab & code-server                                      | (unset)   |
| `TIME_ZONE`             | [Timezone](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) (e.g., `Asia/Seoul`)   | `Etc/UTC` |
| `COMFYUI_EXTRA_ARGS`    | Extra ComfyUI options (e.g. `--fast`)                        | (unset)   |
| `INSTALL_SAGEATTENTION` | Install [SageAttention2](https://github.com/thu-ml/SageAttention) on start (`True`/`False`) | `False`    |
| `PRESET_DOWNLOAD`       | Download model presets into the mounted model storage at startup (comma-separated list). **See below**. | (unset)   |

> 👉 To set: **Edit Pod/Template** → **Add Environment Variable** (Key/Value).

> ⚠️ SageAttention2 requires **Ampere+ GPUs** and ~5 minutes to install.

---

## 🔧 Preset Downloads

> The `PRESET_DOWNLOAD` environment variable accepts either a **single preset** or **multiple presets** separated by commas.\
> (e.g. `WAINSFW_V140` or `WAN22_I2V_A14B_GGUF_Q8_0,WAN22_LIGHTNING_LORA,WAN22_NSFW_LORA`) \
> When set, the container will automatically download the corresponding models on startup.
> Presets are written to the model mount from `extra_model_paths.yaml` (normally `/workspace/models`), and temporary `.part` files are kept under that same mount.

> You can also manually run the preset download script **inside JupyterLab or code-server**:

```bash
bash /download_presets.sh PRESET1,PRESET2,...
```

> 👉 To see which presets are available and view the download list for each, check the [Wiki](https://github.com/somb1/ComfyUI-Docker/wiki/PRESET_DOWNLOAD).

---

## 📁 Logs

| App         | Log Path                                   |
| ----------- | ------------------------------------------ |
| ComfyUI     | `/workspace/ComfyUI/user/comfyui_3000.log` |
| code-server | `/workspace/logs/code-server.log`          |
| JupyterLab  | `/workspace/logs/jupyterlab.log`           |

---

## 📂 Folder Layout

| Path                              | Contents                                                        |
| --------------------------------- | --------------------------------------------------------------- |
| `/opt/ComfyUI`                    | ComfyUI app code and pre-installed custom nodes (in the image)  |
| `/workspace/ComfyUI/models`       | Models                                                          |
| `/workspace/ComfyUI/input`        | Uploaded inputs                                                 |
| `/workspace/ComfyUI/output`       | Generated outputs                                               |
| `/workspace/ComfyUI/user`         | Settings and saved workflows                                    |
| `/workspace/ComfyUI/custom_nodes` | Custom nodes — pre-installed ones are links into `/opt/ComfyUI` |

> To keep your data across Pods, mount a volume at `/workspace` or `/workspace/ComfyUI`. The app code lives outside `/workspace`, so the volume never hides it.\
> Custom nodes you install are kept on the volume, but their Python packages go into the image's environment, so reinstall them on a new Pod.\
> ComfyUI starts as `python /opt/ComfyUI/main.py --base-directory /workspace/ComfyUI ...` (see `/post_start.sh`).\
> Without a volume there, `/workspace/ComfyUI` also looks like the old app folder for scripts that expect it: its other entries link into `/opt/ComfyUI`, and `main.py` is a small shim that runs `/opt/ComfyUI/main.py` with the same data folders.

---

## 🧩 Pre-installed Components

### System

* **OS**: Ubuntu 24.04 (22.02 for CUDA 12.4)
* **Python**: 3.12
* **Framework**: [ComfyUI](https://github.com/comfyanonymous/ComfyUI) + [ComfyUI Manager](https://github.com/Comfy-Org/ComfyUI-Manager) + [JupyterLab](https://jupyter.org/) + [code-server](https://github.com/coder/code-server)
* **Libraries**: PyTorch 2.8.0, CUDA (12.4–12.8), Triton, [hf\_hub](https://huggingface.co/docs/huggingface_hub), [nvtop](https://github.com/Syllo/nvtop)

#### Custom Nodes (only in **base** image)

* ComfyUI-KJNodes
* ComfyUI-WanVideoWrapper
* ComfyUI-GGUF
* ComfyUI-Easy-Use
* ComfyUI-Frame-Interpolation
* ComfyUI-mxToolkit
* ComfyUI-MultiGPU
* ComfyUI_UltimateSDUpscale
* comfyui-prompt-reader-node
* ComfyUI_essentials
* ComfyUI-Impact-Pack
* ComfyUI-Impact-Subpack
* efficiency-nodes-comfyui
* ComfyUI-Custom-Scripts
* ComfyUI_JPS-Nodes
* cg-use-everywhere
* ComfyUI-Crystools
* rgthree-comfy
* ComfyUI-Image-Saver
* comfy-ex-tagcomplete
* ComfyUI-VideoHelperSuite
* ComfyUI-wanBlockswap

> 👉 More details in the [Wiki](https://github.com/somb1/ComfyUI-Docker/wiki/Custom-Nodes).
