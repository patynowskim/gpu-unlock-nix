# gpu-unlock on NixOS

    sudo cp -r ~/gpu-unlock-nix/gpu-unlock.nix ~/gpu-unlock-nix/src /etc/nixos/

In /etc/nixos/flake.nix, add to `modules = [ ... ]`:

    ./gpu-unlock.nix
    { hardware.gpuUnlock.enable = true; hardware.gpuUnlock.targets = "0000:0a:00.0"; }

Then:

    sudo nixos-rebuild boot --flake /etc/nixos#mp && reboot

Check: `journalctl -k -b | grep gpu_unlock`
Undo: boot an older generation, or remove the two lines above and rebuild.
