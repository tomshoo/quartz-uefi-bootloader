{ description = "Nix flake for building Uefi applications";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { flake-utils,
              rust-overlay,
              nixpkgs,
              ...
  }: flake-utils.lib.eachDefaultSystem (system: let
    pkgs = import nixpkgs {
      overlays = [ (import rust-overlay) ];
      localSystem.system = system;
    };

    uefi-builder = pkgs.writeShellScriptBin
      "uefi-builder"
      (builtins.readFile ./scripts/builder.sh);
  in
  { devShells.default = pkgs.mkShell {
      nativeBuildInputs = [ (pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml) ];
      buildInputs       = with pkgs;
        [ qemu
          OVMF
          uefi-builder
          rust-analyzer-unwrapped
        ];

      OVMF_FD_DIR="${pkgs.OVMF.fd}/FV";
    };
  });
}
