"""Declarative configuration loader for repository gates.

Reads gate configuration strictly from pyproject.toml [tool.gates.<gate_name>]
or .gates.toml [tool.gates.<gate_name>] (or [<gate_name>]).
Zero in-code fallback defaults. If required settings are missing, fails fast.
"""
import os
import sys

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        sys.exit("CONFIG ERROR: Python 3.11+ (with built-in tomllib) is required to parse TOML gate configuration.")


def find_repo_root(start: str) -> str:
    """Find the project root by walking up to find pyproject.toml, .gates.toml, or .git."""
    cur = os.path.abspath(start)
    while cur and cur != os.path.dirname(cur):
        if (
            os.path.isfile(os.path.join(cur, "pyproject.toml"))
            or os.path.isfile(os.path.join(cur, ".gates.toml"))
            or os.path.isdir(os.path.join(cur, ".git"))
        ):
            return cur
        cur = os.path.dirname(cur)
    return os.path.abspath(start)


def load_gate_config(start_path: str, gate_name: str, required_keys: list) -> tuple:
    """Load configuration for gate_name.

    Returns:
        (root_path, gate_config_dict)
    """
    root = find_repo_root(start_path)
    candidates = [
        os.path.join(root, "pyproject.toml"),
        os.path.join(root, ".gates.toml"),
    ]

    config_path = None
    data = None

    for c in candidates:
        if os.path.isfile(c):
            config_path = c
            try:
                with open(c, "rb") as f:
                    data = tomllib.load(f)
                break
            except Exception as e:
                sys.exit(f"CONFIG ERROR: Failed to parse TOML configuration '{c}': {e}")

    if not config_path:
        sys.exit(
            f"CONFIG ERROR: No configuration file found for gate '{gate_name}'.\n"
            f"Expected either 'pyproject.toml' or '.gates.toml' in '{root}'.\n"
            f"Declare [tool.gates.{gate_name}] to configure this gate."
        )

    gate_config = (
        data.get("tool", {}).get("gates", {}).get(gate_name)
        or data.get("gates", {}).get(gate_name)
        or data.get(gate_name)
    )

    if gate_config is None:
        sys.exit(
            f"CONFIG ERROR: '{os.path.basename(config_path)}' is missing required section:\n"
            f"  [tool.gates.{gate_name}]\n"
            f"Define this section to run '{gate_name}'."
        )

    missing = [k for k in required_keys if k not in gate_config]
    if missing:
        missing_str = ", ".join(f"'{k}'" for k in missing)
        sys.exit(
            f"CONFIG ERROR: [tool.gates.{gate_name}] in '{os.path.basename(config_path)}' "
            f"is missing required setting(s): {missing_str}."
        )

    return root, gate_config
