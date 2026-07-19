# LazyPi — opinionated one-shot installer that sets up the Pi coding agent with
# a curated catalog of extensions, skills, prompt templates, and themes
# (sub-agents, MCP, web access, memory, plan, diff review, powerbar, usage
# dashboard, themes, …). Upstream: https://github.com/robzolkos/LazyPi
#
# It is a thin Node CLI (single bin/lazypi.mjs + @clack/prompts). At runtime it
# shells out to `pi`, `npm`, and (only for the official Compound Engineering
# package) `bunx`, so those must be on PATH when the user actually runs it —
# packaging only needs Node + npm in the sandbox.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "lazypi";
  version = "0.6.3";

  src = fetchFromGitHub {
    owner = "robzolkos";
    repo = "LazyPi";
    # Tag v0.6.3 (Release Please). Keep rev in sync with the version above.
    rev = "fe728231e61a16b891425ce73a3c382bc9494990";
    hash = "sha256-TltzyaKWlLLLTqcbJGK1g/IWL7+Jf3betoZfBR9CkMo=";
  };

  # Computed with `nix run nixpkgs#prefetch-npm-deps -- package-lock.json`.
  npmDepsHash = "sha256-LfF5cQuqvnbdrNM7gqbFRB+3mKg7VdPAAFTzVVI2sD4=";

  # Insert pi-provider-kimi-code into the LazyPi catalog right after claude-cli
  # (both are core model-provider extensions). This is a local addition —
  # upstream v0.6.3 doesn't ship it — and is mirrored by the `kimi-coding` entry
  # in the lazypiCatalog list in flake-modules/home-modules/pi.nix. We prefer
  # Leechael's pi-provider-kimi-code over picassio's pi-kimi-coder because the
  # former has explicit Kimi K3 support (model id `k3`), live model metadata
  # from /v1/models, plan-aware context windows, and is actively maintained.
  # Keeping the CLI's PACKAGES array in sync means `lazypi status` classifies
  # the provider as part of the catalog instead of "outside the LazyPi catalog".
  # Drop this postPatch (and the matching declarative entry) once upstream
  # LazyPi ships pi-provider-kimi-code in its own catalog.
  postPatch = ''
    substituteInPlace bin/lazypi.mjs \
      --replace-fail \
        '{ id: "claude-cli", category: "core", source: "npm:pi-claude-cli", description: "Claude Code CLI provider", hint: "Use Claude Code CLI auth as a Pi model provider." },' \
        '{ id: "claude-cli", category: "core", source: "npm:pi-claude-cli", description: "Claude Code CLI provider", hint: "Use Claude Code CLI auth as a Pi model provider." },
	{ id: "kimi-coding", category: "core", source: "npm:pi-provider-kimi-code", description: "Kimi Code provider (K3 / K2.7)", hint: "Kimi Code OAuth provider with live model metadata; supports kimi-for-coding, kimi-for-coding-highspeed, and k3. Reuses kimi-cli credentials." },'
  '';

  # No build/prepare script upstream — lazypi is a single interpreted .mjs. We
  # only need `npm install` (handled by npmDepsHash) and the bin shim.
  dontNpmBuild = true;

  meta = with lib; {
    description = "Opinionated one-shot installer for a full-featured Pi coding agent setup";
    homepage = "https://lazypi.org";
    license = licenses.mit;
    mainProgram = "lazypi";
    platforms = platforms.unix ++ platforms.windows;
  };
}
