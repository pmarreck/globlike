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
				let
					pkgs = nixpkgs.legacyPackages.${system};
					zig = zig-overlay.packages.${system}."0.16.0";
					zigDeps = pkgs.stdenv.mkDerivation {
						pname = "globlike-zig-deps";
						version = "0.2.0";
						src = self;
						nativeBuildInputs = [ zig pkgs.git pkgs.cacert ];
						outputHashMode = "recursive";
						outputHashAlgo = "sha256";
						outputHash = "sha256-9jIuIiF4OTst7QTJxEEhDF5rb15b6k3GIPO/mjlZL3o=";
						dontConfigure = true;
						dontFixup = true;
						buildPhase = ''
							export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-fetch
							export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
							export GIT_SSL_CAINFO=$SSL_CERT_FILE
							zig build --fetch=all
						'';
						installPhase = ''
							mkdir -p $out
							cp -r "$ZIG_GLOBAL_CACHE_DIR/p" $out/p
						'';
					};
				in pkgs.stdenv.mkDerivation {
					pname = "globlike";
					version = "0.2.0";
					src = self;
					strictDeps = true;
					nativeBuildInputs = [ zig-overlay.packages.${system}."0.16.0" ];
					dontConfigure = true;
					buildPhase = ''
						runHook preBuild
						export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
						mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
						cp -r ${zigDeps}/p "$ZIG_GLOBAL_CACHE_DIR/"
						chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR"
						zig build ${if checked then "test -Doptimize=ReleaseSafe --summary all" else "-Doptimize=ReleaseFast --prefix $out"} ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-Dtarget=${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux-musl"}
						runHook postBuild
					'';
					installPhase = if checked then "mkdir -p $out; touch $out/passed" else "true";
				};
		in {
			packages = forSystems (system: { default = package system false; });
			checks = forSystems (system: {
				test = package system true;
				cross = (package system false).overrideAttrs (old: {
					buildPhase = old.buildPhase + ''
						for target in x86_64-linux-musl aarch64-linux-musl x86_64-windows-gnu aarch64-windows-gnu aarch64-macos; do
							zig build check -Dtarget=$target -Doptimize=ReleaseSafe
						done
					'';
				});
			});
			devShells = forSystems (system: {
				default = nixpkgs.legacyPackages.${system}.mkShell {
					packages = [ zig-overlay.packages.${system}."0.16.0" ];
				};
			});
		};
}
