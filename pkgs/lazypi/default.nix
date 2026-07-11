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
