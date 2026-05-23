#!/bin/bash

export PYTHONUNBUFFERED=1

echo "**** Setting the timezone based on the TIME_ZONE environment variable. If not set, it defaults to Etc/UTC. ****"
export TZ=${TIME_ZONE:-"Etc/UTC"}
echo "**** Timezone set to $TZ ****"
echo "$TZ" | sudo tee /etc/timezone > /dev/null
sudo ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
sudo dpkg-reconfigure -f noninteractive tzdata

# Update VIRTUAL_ENV paths in all text files under /workspace/venv/bin
update_venv_paths() {
    local bin_dir="/workspace/venv/bin"
    echo "Updating '/venv' to '/workspace/venv' in all text files under '$bin_dir'..."

    find "$bin_dir" -type f | while read -r file; do
        if file "$file" | grep -q "text"; then
            # VIRTUAL_ENV='/venv' → VIRTUAL_ENV='/workspace/venv'
            sed -i "s|VIRTUAL_ENV='/venv'|VIRTUAL_ENV='/workspace/venv'|g" "$file"
            
            # VIRTUAL_ENV '/venv' → VIRTUAL_ENV '/workspace/venv'
            sed -i "s|VIRTUAL_ENV '/venv'|VIRTUAL_ENV '/workspace/venv'|g" "$file"
            
            # #!/venv/bin/python → #!/workspace/venv/bin/python
            sed -i "s|#!/venv/bin/python|#!/workspace/venv/bin/python|g" "$file"

            # Uncomment to debug
            # echo "Updated: $file"
        fi
    done
}

echo "**** syncing venv to workspace, please wait. This could take a while on first startup! ****"
if [ -d /venv ]; then
    IMAGE_STACK_ID="$(cat /venv/.pytorch-stack-id 2>/dev/null || true)"
    WORKSPACE_STACK_ID="$(cat /workspace/venv/.pytorch-stack-id 2>/dev/null || true)"

    if [ -d /workspace/venv ] && [ -n "$IMAGE_STACK_ID" ] && [ "$WORKSPACE_STACK_ID" != "$IMAGE_STACK_ID" ]; then
        echo "**** workspace venv PyTorch stack mismatch; replacing /workspace/venv ****"
        echo "**** image stack: $IMAGE_STACK_ID ****"
        echo "**** workspace stack: ${WORKSPACE_STACK_ID:-missing} ****"
        rm -rf /workspace/venv
    fi

    # When the PyTorch stack matches, /workspace/venv may contain extra packages
    # the user installed at runtime; -u (update-only) preserves them. When the
    # stack mismatches, /workspace/venv was just wiped above, so this still
    # performs a full copy into an empty target.
    if rsync -au /venv/ /workspace/venv/ && rm -rf /venv; then
        update_venv_paths
    fi
else
    echo "Skip: /venv does not exist."
fi

echo "**** syncing ComfyUI to workspace, please wait ****"
if [ -d /ComfyUI ]; then
    EXCLUDE=""
    if [ -d /workspace/ComfyUI/output ]; then
        EXCLUDE="--exclude=output/"
        echo "**** Excluding existing output folder ****"
    fi

    # Sync the image's ComfyUI tree (app code, custom_nodes,
    # user/default/workflows, etc.) into the workspace. Baked models under
    # /ComfyUI/models stay in the image layer and are referenced directly.
    rsync -au --remove-source-files --exclude=/models/ $EXCLUDE /ComfyUI/ /workspace/ComfyUI/

    # Clean up emptied source dirs but keep /ComfyUI/models intact for image
    # variants that bake models there.
    find /ComfyUI -mindepth 1 -type d -empty \
        -not \( -path '/ComfyUI/models' -o -path '/ComfyUI/models/*' \) \
        -delete 2>/dev/null || true

else
    echo "Skip: /ComfyUI does not exist."
fi


if [ "${INSTALL_SAGEATTENTION,,}" = "true" ]; then
    if pip show sageattention > /dev/null 2>&1; then
        echo "**** SageAttention2 is already installed. Skipping installation. ****"
    else
        echo "**** SageAttention2 is not installed. Installing, please wait.... (This may take a long time, approximately 5+ minutes.) ****"
        git clone https://github.com/thu-ml/SageAttention.git /SageAttention
        cd /SageAttention
        export EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" MAX_JOBS=32
        python setup.py install
        echo "**** SageAttention2 installation completed. ****"
    fi
fi

if [ "${INSTALL_CUSTOM_NODES,,}" = "true" ]; then
    if [ -f /install_custom_nodes.sh ]; then
        echo "**** INSTALL_CUSTOM_NODES is set. Running /install_custom_nodes.sh ****"
        /install_custom_nodes.sh
    else
        echo "**** /install_custom_nodes.sh not found. Skipping. ****"
    fi
fi
