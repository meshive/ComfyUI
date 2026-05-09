#!/bin/bash

WGET_OPTS="--show-progress"

if [[ "$1" == "--quiet" ]]; then
    WGET_OPTS="-q"
    shift
fi

MODELS_ROOT="${MODELS_ROOT:-/workspace/models}"
TMP_DIR="${TMP_DIR:-$MODELS_ROOT/.tmp/preset-downloads}"

# download_if_missing <URL> <TARGET_DIR>
download_if_missing() {
    local url="$1"
    local dest_dir="$2"

    local filename
    filename=$(basename "$url")
    local filepath="$dest_dir/$filename"

    mkdir -p "$dest_dir"

    if [ -f "$filepath" ]; then
        echo "File already exists: $filepath (skipping)"
        return
    fi

    echo "Downloading: $filename → $dest_dir"

    local tmpdir="$TMP_DIR"
    mkdir -p "$tmpdir"
    local tmpfile="$tmpdir/${filename}.part"

    if wget $WGET_OPTS -O "$tmpfile" "$url"; then
        mv -f "$tmpfile" "$filepath"
        echo "Download completed: $filepath"
    else
        echo "Download failed: $url"
        rm -f "$tmpfile"
        return 1
    fi
}

IFS=',' read -ra PRESETS <<< "$1"

echo "**** Checking presets and downloading corresponding files ****"

for preset in "${PRESETS[@]}"; do
    case "${preset}" in
        WAINSFW_V140)
            echo "Preset: WAINSFW_V140"
            download_if_missing "https://huggingface.co/Ine007/waiNSFWIllustrious_v140/resolve/main/waiNSFWIllustrious_v140.safetensors" "$MODELS_ROOT/checkpoints"
            ;;
        NTRMIX_V40)
            echo "Preset: NTRMIX_V40"
            download_if_missing "https://huggingface.co/personal1802/NTRMIXillustrious-XLNoob-XL4.0/resolve/main/ntrMIXIllustriousXL_v40.safetensors" "$MODELS_ROOT/checkpoints"
            ;;
        WAN22_TI2V_5B)
            echo "Preset: WAN22_TI2V_5B"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan2.2_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_T2V_A14B)
            echo "Preset: WAN22_T2V_A14B"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_I2V_A14B_FP8_SCALED)
            echo "Preset: WAN22_I2V_A14B_FP8_SCALED"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_I2V_A14B_FP8_E4M3FN_SCALED_KJ)
            echo "Preset: WAN22_I2V_A14B_FP8_E4M3FN_SCALED_KJ"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_2-I2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_2-I2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_I2V_A14B_FP8_E5M2_SCALED_KJ)
            echo "Preset: WAN22_I2V_A14B_FP8_E5M2_SCALED_KJ"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_2-I2V-A14B-HIGH_fp8_e5m2_scaled_KJ.safetensors" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_2-I2V-A14B-LOW_fp8_e5m2_scaled_KJ.safetensors" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_I2V_A14B_GGUF_Q8_0)
            echo "Preset: WAN22_I2V_A14B_GGUF_Q8_0"
            download_if_missing "https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q8_0.gguf" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_high_noise_14B_Q8_0.gguf" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_low_noise_14B_Q8_0.gguf" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_I2V_A14B_GGUF_Q6_K)
            echo "Preset: WAN22_I2V_A14B_GGUF_Q6_K"
            download_if_missing "https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q6_K.gguf" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_high_noise_14B_Q6_K.gguf" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_low_noise_14B_Q6_K.gguf" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_I2V_A14B_GGUF_Q5_K_S)
            echo "Preset: WAN22_I2V_A14B_GGUF_Q5_K_S"
            download_if_missing "https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q5_K_S.gguf" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_high_noise_14B_Q5_K_S.gguf" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_low_noise_14B_Q5_K_S.gguf" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_I2V_A14B_GGUF_Q5_K_M)
            echo "Preset: WAN22_I2V_A14B_GGUF_Q5_K_M"
            download_if_missing "https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q5_K_M.gguf" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_high_noise_14B_Q5_K_M.gguf" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_low_noise_14B_Q5_K_M.gguf" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_I2V_A14B_GGUF_Q4_K_S)
            echo "Preset: WAN22_I2V_A14B_GGUF_Q4_K_S"
            download_if_missing "https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q4_K_S.gguf" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_high_noise_14B_Q4_K_S.gguf" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_low_noise_14B_Q4_K_S.gguf" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_I2V_A14B_GGUF_Q4_K_M)
            echo "Preset: WAN22_I2V_A14B_GGUF_Q4_K_M"
            download_if_missing "https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q4_K_M.gguf" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_high_noise_14B_Q4_K_M.gguf" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_low_noise_14B_Q4_K_M.gguf" "$MODELS_ROOT/diffusion_models"
            ;;
        WAN22_LIGHTNING_LORA)
            echo "Preset: WAN22_LIGHTNING_LORA"
            download_if_missing "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan22-Lightning/Wan2.2-Lightning_I2V-A14B-4steps-lora_HIGH_fp16.safetensors" "$MODELS_ROOT/loras"
            download_if_missing "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan22-Lightning/Wan2.2-Lightning_I2V-A14B-4steps-lora_LOW_fp16.safetensors" "$MODELS_ROOT/loras"
            ;;
        WAN22_NSFW_LORA)
            echo "Preset: WAN22_NSFW_LORA"
            download_if_missing "https://huggingface.co/sombi/comfyui_models/resolve/main/Wan2.2_nsfw_lora_v0.08a/NSFW-22-H-e8.safetensors" "$MODELS_ROOT/loras"
            download_if_missing "https://huggingface.co/sombi/comfyui_models/resolve/main/Wan2.2_nsfw_lora_v0.08a/NSFW-22-L-e8.safetensors" "$MODELS_ROOT/loras"
            ;;
        UPSCALE_MODELS)
            echo "Preset: UPSCALE_MODELS"
            download_if_missing "https://huggingface.co/Comfy-Org/Real-ESRGAN_repackaged/resolve/main/RealESRGAN_x4plus.safetensors" "$MODELS_ROOT/upscale_models"
            download_if_missing "https://huggingface.co/Kim2091/2x-AnimeSharpV4/resolve/main/2x-AnimeSharpV4_RCAN.safetensors" "$MODELS_ROOT/upscale_models"
            download_if_missing "https://huggingface.co/Kim2091/2x-AnimeSharpV4/resolve/main/2x-AnimeSharpV4_Fast_RCAN_PU.safetensors" "$MODELS_ROOT/upscale_models"
            ;;
        WAN22_S2V_FP8_SCALED)
            echo "Preset: WAN22_S2V_FP8_SCALED"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/audio_encoders/wav2vec2_large_english_fp16.safetensors" "$MODELS_ROOT/audio_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_s2v_14B_fp8_scaled.safetensors" "$MODELS_ROOT/diffusion_models"
            ;;
        Z_IMAGE_TURBO)
            echo "Preset: Z_IMAGE_TURBO"
            download_if_missing "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" "$MODELS_ROOT/text_encoders"
            download_if_missing "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors" "$MODELS_ROOT/diffusion_models"
            download_if_missing "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" "$MODELS_ROOT/vae"
            download_if_missing "https://huggingface.co/tarn59/pixel_art_style_lora_z_image_turbo/resolve/main/pixel_art_style_z_image_turbo.safetensors" "$MODELS_ROOT/loras"
            download_if_missing "https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors" "$MODELS_ROOT/model_patches"
            ;;
        *)
            echo "No matching preset for '${preset}', skipping."
            ;;
    esac
done
