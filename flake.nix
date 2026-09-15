{
	description = "Portable glob patterns with inline PCRE2 excerpts";
	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/6dedf69f94d03cbe7bdde106f2d4c23ae2a853bf";
		zig-overlay = {
			url = "github:mitchellh/zig-overlay/5b4b89d060609b448df810bc55f04d003089237a";
			inputs.nixpkgs.follows = "nixpkgs";
		};
	};
	outputs = { self, nixpkgs, zig-overlay }:
		let
			systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
			forSystems = nixpkgs.lib.genAttrs systems;
			package = system: checked:
				let pkgs = nixpkgs.legacyPackages.${system};
				in pkgs.stdenv.mkDerivation {
					pname = "globlike";
					version = "0.1.0";
					src = self;
					strictDeps = true;
					nativeBuildInputs = [ zig-overlay.packages.${system}."0.16.0" ];
					dontConfigure = true;
					buildPhase = ''
						runHook preBuild
						export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
						zig build ${if checked then "test -Doptimize=ReleaseSafe --summary all" else "-Doptimize=ReleaseFast --prefix $out"}
						runHook postBuild
					'';
					installPhase = if checked then "mkdir -p $out; touch $out/passed" else "true";
				};
		in {
			packages = forSystems (system: { default = package system false; });
			checks = forSystems (system: { test = package system true; });
			devShells = forSystems (system: {
				default = nixpkgs.legacyPackages.${system}.mkShell {
					packages = [ zig-overlay.packages.${system}."0.16.0" ];
				};
			});
		};
}
