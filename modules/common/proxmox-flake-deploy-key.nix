# modules/common/proxmox-flake-deploy-key.nix
# SSH-config + known_hosts für read-only Pull aus dem privaten achimcc/proxmox-
# Repo (flake-input für DNS-SSoT, siehe flake.nix:inputs.proxmox).
# Der private deploy-key kommt via sops aus secrets/proxmox-readonly.yaml.
{ ... }:
{
  # github.com hardcoded für nix-flake-update — überschreibt System-Defaults
  # nur für github.com. Alle anderen SSH-Ziele bleiben unberührt.
  programs.ssh.extraConfig = ''
    Host github.com
      User git
      IdentityFile /run/secrets/proxmox_readonly_key
      IdentitiesOnly yes
  '';

  # Pinned ed25519 host-key von github.com (Stand 2026-04-28, abrufbar via
  # `ssh-keyscan -t ed25519 github.com` oder GitHub-Dokumentation).
  # Verhindert StrictHostKeyChecking-Prompt beim ersten nixos-rebuild.
  programs.ssh.knownHosts."github.com" = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };
}
