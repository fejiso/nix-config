# kimi-cli — Moonshot AI's "Kimi Code CLI" (PyPI: kimi-cli), a terminal AI
# coding agent (command `kimi`). It is also the credential source that the
# pi-kimi-coder extension auto-imports: when a user runs `kimi login`, tokens
# land in ~/.kimi/credentials/kimi-code.json, and pi-kimi-coder reads them for
# zero-config auth (see https://github.com/picassio/pi-kimi-coder).
#
# Upstream is a uv workspace (build backend `uv_build`) whose members kosong /
# pykaos are NOT in nixpkgs and have no standalone equivalent, so we vendor
# those (plus streamingjson and ripgrepy, also absent from nixpkgs) below.
# kimi-cli itself ships as a pure-python py3-none-any wheel — we install that
# directly (format = "wheel") to skip the non-standard uv_build backend and the
# workspace-member resolution the sdist would need.
#
# kimi-cli pins many deps to exact == versions; we accept nixpkgs' (close)
# versions for everything available and only vendor what's truly missing. The
# two platform/python guards in upstream's deps are dropped on Linux+py3.12:
#   - batrachian-toad (python_version >= "3.14")  — N/A on 3.12
#   - pyobjc-framework-cocoa (sys_platform == "darwin") — N/A on Linux
{
  lib,
  python3,
  fetchurl,
  fetchPypi,
  ripgrep,
}:

let
  # scalar-fastapi (a kimi-cli transitive dep) ships no tests, but nixpkgs'
  # pytestCheckHook treats pytest-9's "0 tests collected" exit code 5 as a
  # failure, so a from-source build aborts. Skip its pytest phase. Scoped to
  # kimi-cli's python env so it doesn't touch the rest of the config.
  py = (python3.override {
    packageOverrides = self: super: {
      scalar-fastapi = super.scalar-fastapi.overridePythonAttrs (_: {
        dontUsePytestCheck = true;
      });
    };
  }).pkgs;

  # --- vendored deps not in nixpkgs ------------------------------------------
  # All four are pure-python; kosong/pykaos/streamingjson ship wheels, ripgrepy
  # is sdist-only (setuptools, zero install_requires).

  # LLM abstraction layer used by kimi-cli. kimi-cli requires `kosong[contrib]`;
  # the `contrib` extra only re-adds anthropic + google-genai, both already in
  # the base dep set, so no extra inputs are needed beyond kosong's base list.
  kosong = py.buildPythonPackage rec {
    pname = "kosong";
    version = "0.55.0";
    format = "wheel";
    # kosong pins openai<2.15 etc.; nixpkgs' newer (API-stable) versions are
    # supplied via propagatedBuildInputs above, so skip the wheel's pin check.
    dontCheckRuntimeDeps = true;
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/80/5d/cd70aee5aea36a9ee26790213c0d755bf47fbd024946bf32662d7e4c1e73/kosong-0.55.0-py3-none-any.whl";
      hash = "sha256-yTrATjpS8ibsRynWoLvd4emqE7Q7ewRPtO/cX2j/jOs=";
    };
    propagatedBuildInputs = [
      py.anthropic
      py.google-genai
      py.jsonschema
      py.loguru
      py.openai
      py.pydantic
      py.python-dotenv
      py.typing-extensions
      py.mcp
    ];
    doCheck = false;
  };

  # KAOS agent runtime companion (aiofiles + asyncssh).
  pykaos = py.buildPythonPackage rec {
    pname = "pykaos";
    version = "0.9.0";
    format = "wheel";
    dontCheckRuntimeDeps = true;
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/80/26/e3b800793ced194a8e1a1a3f6dbfbb2b48231cdfcb0aecc8f52ec890a09a/pykaos-0.9.0-py3-none-any.whl";
      hash = "sha256-pyWRD/FnEx29qR5QL0DDtf+LZ2UjWOzdgQoOAzl3XhA=";
    };
    propagatedBuildInputs = [
      py.aiofiles
      py.asyncssh
    ];
    doCheck = false;
  };

  streamingjson = py.buildPythonPackage rec {
    pname = "streamingjson";
    version = "0.0.5";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/47/60/3b1680ea91cc95a2088164ae67f91960b93ec568027ccb4b47784b7f5efa/streamingjson-0.0.5-py3-none-any.whl";
      hash = "sha256-x7rs4P9+vOCiprqgwTlN/f4kpKYvljXUoXwrVI/163Y=";
    };
    doCheck = false;
  };

  # Python wrapper around the `rg` binary. No Python deps; just needs ripgrep
  # on PATH at runtime (wired via makeWrapperArgs below on kimi-cli).
  ripgrepy = py.buildPythonPackage rec {
    pname = "ripgrepy";
    version = "2.2.0";
    pyproject = true;
    build-system = [ py.setuptools ];
    src = fetchPypi {
      inherit pname version;
      hash = "sha256-TEPGE4TyV2YAB6zScaXY5KvpvgsGnEGNCR9ymeCAyp0=";
    };
    doCheck = false;
  };
in

  py.buildPythonApplication rec {
  pname = "kimi-cli";
  version = "1.49.0";
  format = "wheel";

  # kimi-cli and its vendored deps pin many deps to exact == versions that
  # don't match nixpkgs (asyncssh 2.22 vs ==2.21.1, openai 2.33 vs <2.15, …).
  # Skip the wheel's runtime-deps version check — the curated
  # propagatedBuildInputs below supply API-compatible nixpkgs versions. (We
  # can't use pythonRelaxDeps here: it rewrites the wheel METADATA, which then
  # breaks the RECORD hash check at install time.)
  dontCheckRuntimeDeps = true;

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/31/44/677c07fcefb99bf28eefed1248fddc4880801576dd5aee911c9e6492c265/kimi_cli-1.49.0-py3-none-any.whl";
    hash = "sha256-Og7WMr7Zf4vwVAMwnqOCMDEFHKJyZP9tXysrAbyQl24=";
  };

  # Everything kimi-cli needs that nixpkgs already provides, plus the four
  # vendored packages above. Versions follow nixpkgs (kimi-cli's exact == pins
  # are mostly already matched: pillow 12.2.0, pyyaml 6.0.3, pydantic 2.12.5,
  # httpx 0.28.1, tomlkit 0.14.0, jinja2 3.1.6, prompt-toolkit 3.0.52).
  propagatedBuildInputs = [
    kosong
    pykaos
    streamingjson
    ripgrepy
    py.agent-client-protocol
    py.aiofiles
    py.aiohttp
    py.typer
    py.loguru
    py.prompt-toolkit
    py.pillow
    py.pyyaml
    py.rich
    py.trafilatura
    py.lxml
    py.tenacity
    py.fastmcp
    py.pydantic
    py.httpx
    py.tomlkit
    py.jinja2
    py.fastapi
    py.uvicorn
    py.scalar-fastapi
    py.websockets
    py.keyring
    py.setproctitle
  ];

  # ripgrepy shells out to `rg`; make sure the binary is resolvable when kimi
  # invokes the agent's built-in grep tool.
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [ ripgrep ])
  ];

  # kimi-cli ships no test suite in the wheel.
  doCheck = false;

  # The wheel records a pile of exact == pins that don't all match nixpkgs; we
  # map them manually above, so don't let the generic hook second-guess us.
  pythonImportCheck = [ "kimi_cli" ];

  meta = with lib; {
    description = "Kimi Code CLI — Moonshot AI's terminal coding agent";
    homepage = "https://github.com/MoonshotAI/kimi-cli";
    license = licenses.mit;
    mainProgram = "kimi";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
