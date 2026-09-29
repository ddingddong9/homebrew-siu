#!/usr/bin/env python3
"""Bundle Homebrew dylibs for an Apple Silicon macOS 26 LAN test app."""

import argparse
import collections
import pathlib
import shutil
import subprocess
import tempfile


def run(*args):
    return subprocess.check_output(args, text=True)


def dependencies(binary):
    lines = run("otool", "-L", str(binary)).splitlines()[1:]
    return [line.strip().split(" (", 1)[0] for line in lines]


def resolve_dependency(origin, name):
    if name.startswith(("/usr/lib/", "/System/Library/")):
        return None
    if name.startswith("/opt/homebrew/"):
        candidate = pathlib.Path(name)
    elif name.startswith("@loader_path/"):
        candidate = origin.parent / name.removeprefix("@loader_path/")
    elif name.startswith("@rpath/"):
        relative = name.removeprefix("@rpath/")
        candidate = next((p for p in (origin.parent / relative,
                          origin.parent.parent / "lib" / relative,
                          pathlib.Path("/opt/homebrew/lib") / relative) if p.exists()), None)
        if candidate is None:
            raise RuntimeError(f"Cannot resolve {name} from {origin}")
    elif name == str(origin):
        return origin
    else:
        raise RuntimeError(f"Unexpected dependency {name} in {origin}")
    if not candidate.exists():
        raise RuntimeError(f"Missing dependency {candidate}")
    resolved = candidate.resolve()
    if not resolved.is_relative_to("/opt/homebrew/Cellar/"):
        raise RuntimeError(f"Dependency is outside Homebrew Cellar: {resolved}")
    return resolved


def bundle_name(origin):
    parts = origin.relative_to("/opt/homebrew/Cellar/").parts
    return f"{parts[0]}--{parts[1]}--{origin.name}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=pathlib.Path, help="Built development SIU Football.app")
    parser.add_argument("output", type=pathlib.Path, help="Destination zip file")
    args = parser.parse_args()
    source = args.source.resolve()
    if not (source / "Contents/MacOS/gameplayfootball").is_file():
        parser.error("source is not a built SIU Football.app")
    if not (source / "Contents/MacOS/siu").is_file():
        parser.error("source is missing the lobby executable")

    roots = [source / "Contents/MacOS/gameplayfootball", source / "Contents/MacOS/siu"]
    queued = collections.deque(roots)
    graph = {}
    while queued:
        origin = queued.popleft().resolve()
        if origin in graph:
            continue
        edges = []
        for name in dependencies(origin):
            target = resolve_dependency(origin, name)
            if target is not None and target != origin:
                edges.append((name, target))
                queued.append(target)
        graph[origin] = edges

    with tempfile.TemporaryDirectory(prefix="siu-football-test-") as temporary:
        staging = pathlib.Path(temporary)
        app = staging / "SIU Football.app"
        shutil.copytree(source, app)
        # The development-only shell launcher is not used by this app and
        # cannot be sealed as a Mach-O code object inside Contents/MacOS.
        (app / "Contents/MacOS/launch-gameplayfootball").unlink(missing_ok=True)
        frameworks = app / "Contents/Frameworks"
        frameworks.mkdir()
        destinations = {
            roots[0].resolve(): app / "Contents/MacOS/gameplayfootball",
            roots[1].resolve(): app / "Contents/MacOS/siu",
        }
        libraries = [origin for origin in graph if origin not in destinations]
        for origin in libraries:
            destination = frameworks / bundle_name(origin)
            shutil.copy2(origin, destination)
            destinations[origin] = destination

        for origin, edges in graph.items():
            destination = destinations[origin]
            if origin in libraries:
                subprocess.run(["install_name_tool", "-id",
                                "@rpath/" + destination.name, str(destination)],
                               check=True, capture_output=True, text=True)
            for old, target in edges:
                prefix = "@loader_path/" if origin in libraries else "@executable_path/../Frameworks/"
                new = prefix + destinations[target].name
                subprocess.run(["install_name_tool", "-change", old, new, str(destination)],
                               check=True, capture_output=True, text=True)

        for destination in destinations.values():
            remaining = [name for name in dependencies(destination)
                         if name.startswith("/opt/homebrew/")]
            if remaining:
                raise RuntimeError(f"Unbundled dependencies in {destination}: {remaining}")

        manifest = ["SIU Football macOS 26 Apple Silicon LAN test build", "",
                    "Bundled Homebrew binary dependencies:"]
        for origin in sorted(libraries):
            manifest.append(f"{bundle_name(origin)} <- {origin}")
        (app / "Contents/Resources/BUNDLED-LIBRARIES.txt").write_text("\n".join(manifest) + "\n")
        license_dir = app / "Contents/Resources/ThirdPartyLicenses"
        fallback_dir = pathlib.Path(__file__).resolve().parent.parent / "Licenses/GameplayFootball"
        formula_roots = sorted({origin.parents[1] for origin in libraries})
        for formula_root in formula_roots:
            formula_name = formula_root.parent.name
            installed_notices = [path for path in formula_root.rglob("*")
                                 if path.is_file() and path.name.lower().startswith(
                                     ("license", "copying", "copyright"))]
            if not installed_notices:
                fallback = next(fallback_dir.glob(formula_name + "-*"), None)
                if fallback is None:
                    raise RuntimeError(f"Missing license notice for {formula_name}")
                installed_notices = [fallback]
            for notice in installed_notices:
                relative = (notice.relative_to(formula_root) if notice.is_relative_to(formula_root)
                            else pathlib.Path(notice.name))
                target = license_dir / formula_name / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(notice, target)
        vendor_root = pathlib.Path(__file__).resolve().parent.parent / "Vendor/GameplayFootball"
        for source_notice, relative in (
            (vendor_root / "LICENSE", "GameplayFootball/LICENSE"),
            (vendor_root / "data/media/fonts/alegreya/OFL.txt", "Alegreya/OFL.txt"),
        ):
            target = license_dir / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_notice, target)

        for destination in destinations.values():
            subprocess.check_call(["codesign", "--force", "--sign", "-", str(destination)],
                                  stdout=subprocess.DEVNULL)
        subprocess.check_call(["codesign", "--force", "--deep", "--sign", "-", str(app)],
                              stdout=subprocess.DEVNULL)
        subprocess.check_call(["codesign", "--verify", "--deep", "--strict", str(app)])

        output = args.output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.check_call(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
                               str(app), str(output)])
        print(f"Portable test app: {output}")
        print(f"Bundled libraries: {len(libraries)}")


if __name__ == "__main__":
    main()
