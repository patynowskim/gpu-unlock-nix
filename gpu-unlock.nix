# NixOS module for https://github.com/Zagitta/gpu-unlock (commit 6081407).
# Usage: imports = [ ./gpu-unlock.nix ]; hardware.gpuUnlock.enable = true;
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.gpuUnlock;
  nv = "610.43.03";

  nvSource = pkgs.fetchurl {
    url = "https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/NVIDIA-kernel-module-source-${nv}.tar.xz";
    sha256 = "1p61kzz2vb770cia95c6z6d4xq738qx2fqsd24vdqgm2qwiqj4by";
  };
  nvInstaller = pkgs.fetchurl {
    url = "https://download.nvidia.com/XFree86/Linux-x86_64/${nv}/NVIDIA-Linux-x86_64-${nv}-no-compat32.run";
    sha256 = "141gzqc47s05a95xkxs5r7ikdln495bnakypsclxz9ihnwflb170";
  };

  # Firmware extracted from the pinned NVIDIA driver (same as `make firmware`).
  firmware = pkgs.stdenvNoCC.mkDerivation {
    pname = "gpu-unlock-firmware";
    version = nv;
    src = ./src;
    nativeBuildInputs = [ pkgs.python3 pkgs.zstd pkgs.openssl ];
    dontConfigure = true;
    buildPhase = ''
      mkdir -p assets nvsrc
      tar -xf ${nvSource} -C nvsrc
      python3 firmware/extract_gsp.py ${nvInstaller} assets
      python3 firmware/extract_boot_assets.py nvsrc/NVIDIA-kernel-module-source-${nv} assets
    '';
    installPhase = ''
      d=$out/lib/firmware/gpu-unlock/${nv}
      mkdir -p $d
      for f in booter_load_ad102 booter_load_ga102 gsp_boot_ad102 gsp_boot_desc_ad102 \
               booter_load_ga100 gsp_boot_ga102 gsp_boot_desc_ga102 gsp_boot_ga100 \
               gsp_boot_desc_ga100; do
        install -Dm644 assets/$f.bin $d/$f.bin
      done
      for f in falcon_loader gsp_ga10x gsp_tu10x; do
        install -Dm644 assets/$f.bin $d/$f.bin
      done
    '';
    meta.license = lib.licenses.unfree;
  };

  module = kernel: pkgs.stdenv.mkDerivation {
    pname = "gpu-unlock";
    version = "1.1.0";
    src = ./src;
    nativeBuildInputs = kernel.moduleBuildDependencies;
    hardeningDisable = [ "pic" "format" ];
    makeFlags = (builtins.filter (f: !(lib.hasPrefix "O=" f || lib.hasPrefix "--eval" f)) kernel.makeFlags) ++ [
      "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    ];
    preBuild = "cd kernel/gpu_unlock";
    installPhase = ''
      install -Dm644 gpu_unlock.ko \
        $out/lib/modules/${kernel.modDirVersion}/extra/gpu_unlock.ko
    '';
    meta.license = lib.licenses.gpl2Only;
  };
in
{
  options.hardware.gpuUnlock = {
    enable = lib.mkEnableOption "Ampere FP16/BF16 pre-driver unlock (gpu-unlock)";
    targets = lib.mkOption {
      type = lib.types.str;
      default = "all";
      example = "0000:0a:00.0";
      description = "Value of gpu_unlock.targets= (\"all\" or comma-separated PCI addresses).";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.extraModulePackages = [ (module config.boot.kernelPackages.kernel) ];
    hardware.firmware = [ firmware ];
    # Load in the initrd, before nvidia binds the card from the root filesystem.
    boot.initrd.kernelModules = [ "gpu_unlock" ];
    boot.kernelParams = [ "gpu_unlock.targets=${cfg.targets}" ];
  };
}
