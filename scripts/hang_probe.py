#!/usr/bin/env python3
"""Opens the demo on a simulator at a given screen and tells whether the app still answers.

CI's "Hang probe" step (.github/workflows/ios.yml) runs it after the app's build. For each
screen (`-ScreenshotScreen`, ios/Platina/Support/ScreenshotDemo) it launches the demo, waits
for the screen to open, then reads the app's main thread with `sample`: a main thread that
spends its time anywhere but waiting in its run loop is a hang, and its heaviest frames say
where. It also prints the app's CPU and SwiftUI's warnings from the system log (an update loop
shows there as "... tried to update multiple times per frame").

    python3 scripts/hang_probe.py --device <udid> --app <Platina.app> pathGame game pathGame+loop

`pathGame+loop` launches with UIKit's layout feedback loop debugging: UIKit names the views of
a layout that never settles and stops the app; the step prints its log and the crash report.
Exit status 1 when any screen hung.
"""
import argparse
import collections
import json
import re
import subprocess
import sys
import time
from pathlib import Path

BUNDLE = "dakacom.Platina"
PROCESS = "Platina"
LOG_KEYWORDS = re.compile(
    r"multiple times per frame|cycle|AttributeGraph|navigationDestination|Modifying state|"
    r"Publishing changes|NavigationRequestObserver|NavigationAuthority|runaway|"
    r"exceeded|Invalid Configuration|fault",
    re.IGNORECASE,
)


def run(*args: str, check: bool = False) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"{' '.join(args)}: {result.stderr.strip()}")
    return result.stdout + result.stderr


def cpu(pid: int) -> str:
    return run("ps", "-o", "%cpu=", "-p", str(pid)).strip() or "gone"


def main_thread(sample: str) -> list[tuple[int, int, str]]:
    """The main thread's call graph from `sample`: (depth, samples, frame) per line."""
    lines = sample.splitlines()
    # `sample` names it "DispatchQueue_1: com.apple.main-thread" or "Main Thread" (Xcode 27).
    start = next((i for i, line in enumerate(lines)
                  if "com.apple.main-thread" in line or ": Main Thread" in line), None)
    if start is None:
        return []
    frames = []
    pattern = re.compile(r"^(\s*[+!:| ]*)(\d+)\s+(.*)$")
    for line in lines[start:]:
        if not line.strip() or (frames and re.match(r"^\s{4}\d+\s+Thread_", line)):
            break
        match = pattern.match(line)
        if match:
            frames.append((len(match.group(1)), int(match.group(2)), match.group(3)))
    return frames


def crash_report(since: float) -> None:
    """The newest crash report of the app since `since`: its exception, reason and backtrace."""
    folder = Path.home() / "Library/Logs/DiagnosticReports"
    reports = sorted((path for path in folder.glob(f"{PROCESS}*.ips") if path.stat().st_mtime >= since),
                     key=lambda path: path.stat().st_mtime)
    if not reports:
        print("No crash report.")
        return
    text = reports[-1].read_text(errors="replace")
    body = json.loads(text[text.index("\n") + 1:])
    print("Crash:", json.dumps(body.get("exception", {}))[:300])
    for line in json.dumps(body.get("asi", {}), ensure_ascii=False)[:3000].split("\\n"):
        print("  ", line)
    frames = body.get("lastExceptionBacktrace") or next(
        (thread.get("frames", []) for thread in body.get("threads", []) if thread.get("triggered")), [])
    images = body.get("usedImages", [])
    for frame in frames[:70]:
        image = images[frame.get("imageIndex", 0)].get("name", "?") if images else "?"
        print(f"   {image}: {frame.get('symbol', hex(frame.get('imageOffset', 0)))}")


def probe(device: str, screen: str, out: Path, wait: float) -> bool:
    print(f"\n=== {screen} ===", flush=True)
    # `name+loop`: UIKit's layout feedback loop debugging, which names the views of a layout
    # that does not settle and stops the app with an exception.
    screen, _, mode = screen.partition("+")
    extra = ["-UIViewLayoutFeedbackLoopDebuggingThreshold", "50"] if mode == "loop" else []
    started = time.time()
    run("xcrun", "simctl", "terminate", device, BUNDLE)
    log_path = out / f"log-{screen}{'-' + mode if mode else ''}.txt"
    log_file = log_path.open("w")
    stream = subprocess.Popen(
        ["xcrun", "simctl", "spawn", device, "log", "stream", "--style", "compact", "--level", "debug",
         "--predicate", f'process == "{PROCESS}"'],
        stdout=log_file, stderr=subprocess.STDOUT,
    )
    launched = run("xcrun", "simctl", "launch", device, BUNDLE,
                   "-ScreenshotDemo", "-ScreenshotScreen", screen,
                   "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", *extra)
    match = re.search(r":\s*(\d+)\s*$", launched.strip())
    if not match:
        print(f"Did not launch: {launched.strip()}")
        stream.terminate()
        return False
    pid = int(match.group(1))
    print(f"pid {pid}", flush=True)

    readings = []
    end = time.time() + wait
    while time.time() < end:
        time.sleep(5)
        readings.append(cpu(pid))
    print("CPU every 5 s:", " ".join(readings), flush=True)

    if mode == "loop":
        stream.terminate()
        log_file.close()
        alive = cpu(pid) != "gone"
        print("The app", "still runs" if alive else "stopped", flush=True)
        if not alive:
            print(f"::error title=Hang probe::{screen}: the app stopped (a layout feedback loop?)")
        lines = [line for line in log_path.read_text(errors="replace").splitlines()
                 if re.search(r"(?i)feedback|layout ?loop|exception|setNeedsLayout|Terminating", line)]
        print(f"UIKit on the layout loop ({len(lines)} lines):")
        for line in lines[:150]:
            print("  ", line[:400])
        crash_report(started)
        run("xcrun", "simctl", "terminate", device, BUNDLE)
        return alive

    sample_path = out / f"sample-{screen}.txt"
    run("sudo", "-n", "sample", str(pid), "2", "-mayDie", "-file", str(sample_path))
    stream.terminate()
    log_file.close()

    hung = False
    if sample_path.exists():
        frames = main_thread(sample_path.read_text(errors="replace"))
        if frames:
            total = frames[0][1]
            idle = sum(count for _, count, frame in frames if frame.startswith("mach_msg2_trap"))
            share = idle / total if total else 0
            hung = share < 0.5
            print(f"Main thread: {total} samples, waiting in its run loop {share:.0%}"
                  f" -> {'HUNG' if hung else 'answers'}")
            if hung:
                print(f"::error title=Hang probe::{screen}: the main thread waits {share:.0%} of the time")
            if hung:
                heavy = [(depth, count, frame) for depth, count, frame in frames if count >= total * 0.3]
                own = list(dict.fromkeys(frame.split("  (in ")[0] for _, _, frame in heavy
                                         if "(in Platina" in frame))
                print("The app's own frames among them:", *own[:40], sep="\n  ")
                if len(heavy) > 160:
                    heavy = heavy[:40] + [(0, 0, "…")] + heavy[-120:]
                print("Heaviest frames of the main thread:")
                for depth, count, frame in heavy:
                    print(f"{' ' * min(depth, 60)}{count} {frame[:220]}")
        else:
            print("No main thread in the sample:")
            print(sample_path.read_text(errors="replace")[:3000])
    else:
        print("No sample (the app may have exited).")

    messages = collections.Counter()
    for line in log_path.read_text(errors="replace").splitlines():
        if LOG_KEYWORDS.search(line):
            text = re.sub(r"^\S+\s+\S+\s+\S+\s+", "", line)
            text = re.sub(r"0x[0-9a-f]+", "0x…", text)
            messages[text[:300]] += 1
    if messages:
        print("System log, SwiftUI's warnings and faults:")
        for text, count in messages.most_common(40):
            print(f"  {count}× {text}")
    run("xcrun", "simctl", "terminate", device, BUNDLE)
    return not hung


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--out", default="hang-probe")
    parser.add_argument("--wait", type=float, default=40)
    parser.add_argument("screens", nargs="+")
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    run("xcrun", "simctl", "boot", args.device)
    run("xcrun", "simctl", "bootstatus", args.device, "-b")
    run("xcrun", "simctl", "install", args.device, args.app, check=True)
    results = {screen: probe(args.device, screen, out, args.wait) for screen in args.screens}
    run("xcrun", "simctl", "shutdown", args.device)

    print("\n" + "  ".join(f"{screen}: {'answers' if ok else 'HUNG'}" for screen, ok in results.items()))
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
