#!/usr/bin/env python3
"""Collect macOS process usage and Flutter VM samples; standard library only."""
import argparse
import ctypes
import gzip
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import time
from urllib.parse import urlencode
from urllib.request import urlopen


class Usage(ctypes.Structure):
    # rusage_info_v0 from sys/resource.h; Apple Silicon CPU times use Mach ticks.
    _fields_ = [("uuid", ctypes.c_ubyte * 16)] + [
        (name, ctypes.c_uint64) for name in
        ("user", "system", "idle", "interrupt", "pageins", "wired",
         "resident", "footprint", "start", "exit")
    ]


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


def distribution(values):
    ordered = sorted(values)
    if not ordered:
        return None
    return {"mean": statistics.mean(ordered), "median": statistics.median(ordered),
            "p95": ordered[math.ceil(len(ordered) * .95) - 1],
            "min": ordered[0], "max": ordered[-1]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("uri", help="HTTP VM service URI from flutter run")
    parser.add_argument("output", type=Path)
    parser.add_argument("--seconds", type=int, default=20)
    args = parser.parse_args()
    assert args.seconds >= 10
    assert distribution([1, 2, 3, 4])["median"] == 2.5
    assert ctypes.sizeof(Usage) == 96
    args.output.mkdir(parents=True, exist_ok=True)

    def rpc(method, **params):
        query = urlencode({k: str(v).lower() if isinstance(v, bool) else v
                           for k, v in params.items()})
        with urlopen(f"{args.uri.rstrip('/')}/{method}?{query}", timeout=60) as response:
            data = json.load(response)
        if "error" in data:
            raise RuntimeError(f"{method}: {data['error']}")
        return data["result"]

    vm = rpc("getVM")
    isolate = next(item["id"] for item in vm["isolates"] if item["name"] == "main")

    def control(**params):
        return rpc("ext.pomodoist.resourceProfile", isolateId=isolate, **params)

    initial = control()
    pid = initial["pid"]
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
    timebase = Timebase()
    if ctypes.CDLL("/usr/lib/libSystem.B.dylib").mach_timebase_info(ctypes.byref(timebase)):
        raise RuntimeError("Cannot read Mach timebase")
    ns_per_tick = timebase.numer / timebase.denom

    def usage():
        value = Usage()
        if libproc.proc_pid_rusage(pid, 0, ctypes.byref(value)) != 0:
            raise RuntimeError(f"Cannot sample pid {pid}")
        return value

    before_calibration, after_calibration = Usage(), Usage()
    libproc.proc_pid_rusage(os.getpid(), 0, ctypes.byref(before_calibration))
    cpu_start = time.process_time_ns()
    while time.process_time_ns() - cpu_start < 100_000_000:
        pass
    elapsed_cpu_ns = time.process_time_ns() - cpu_start
    libproc.proc_pid_rusage(os.getpid(), 0, ctypes.byref(after_calibration))
    calibrated_ns = (after_calibration.user + after_calibration.system
                     - before_calibration.user - before_calibration.system) * ns_per_tick
    assert abs(calibrated_ns / elapsed_cpu_ns - 1) < .1, (calibrated_ns, elapsed_cpu_ns)

    metadata = {"vm": vm, "initial": initial, "seconds_per_phase": args.seconds,
                "cpu_timebase": {"numer": timebase.numer, "denom": timebase.denom,
                                 "calibration_ratio": calibrated_ns / elapsed_cpu_ns},
                "hardware": subprocess.check_output(
                    ["sysctl", "hw.model", "hw.memsize", "hw.logicalcpu",
                     "machdep.cpu.brand_string"], text=True),
                "source": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
                "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    rpc("setVMTimelineFlags", recordedStreams="[Dart,Embedder,GC]")
    rpc("clearCpuSamples", isolateId=isolate)
    profile_origin = rpc("getVMTimelineMicros")["timestamp"]
    results = []
    try:
        for label, mode in [("hidden_cold", "hidden"), ("animated_1", "animated"),
                            ("static_1", "static"), ("hidden_warm_1", "hidden"),
                            ("animated_2", "animated"), ("static_2", "static"),
                            ("hidden_warm_2", "hidden")]:
            print(f"Warmup: {label}", flush=True)
            control(mode=mode)
            time.sleep(10)
            status = control(record=True)
            assert status["error"] is None and not status["flutterErrors"], status
            assert status["widgets"]["TodayScreen"] > 0, status
            assert status["widgets"]["_StartupLoading"] == 0, status
            assert status["visible"] == (mode != "hidden"), status
            assert status["widgets"]["PomoModel"] == (0 if mode == "hidden" else 1), status
            if mode != "hidden":
                assert status["widgets"]["Texture"] > 0, status
                assert status["animated"] == (mode == "animated"), status
            native_start = status["nativeScheduler"]["scheduledFrames"]
            rpc("clearVMTimeline")
            origin = rpc("getVMTimelineMicros")["timestamp"]
            before = usage()
            previous_time = start = time.monotonic()
            samples = []
            for index in range(args.seconds):
                time.sleep(max(0, start + index + 1 - time.monotonic()))
                current = usage()
                now = time.monotonic()
                memory = rpc("getMemoryUsage", isolateId=isolate)
                live = control()
                samples.append({"elapsed_s": now - start,
                    "cpu_ticks": current.user + current.system - before.user - before.system,
                    "cpu_interval_s": now - previous_time,
                    "cpu_one_core_percent": (current.user + current.system - before.user - before.system)
                        * ns_per_tick / 1e9 / (now - previous_time) * 100,
                    "rss_bytes": current.resident, "footprint_bytes": current.footprint,
                    "dart": memory, "native_scheduler": live["nativeScheduler"],
                    "lifecycle": live["lifecycle"]})
                before, previous_time = current, now
            end = rpc("getVMTimelineMicros")["timestamp"]
            status = control(record=False)
            assert status["error"] is None and not status["flutterErrors"], status
            trace = rpc("getVMTimeline", timeOriginMicros=origin, timeExtentMicros=end-origin)
            process_memory = rpc("getProcessMemoryUsage")
            (args.output / f"{label}-timeline.json").write_text(json.dumps(trace))
            frames = status.pop("frames")
            summary = {"label": label, "mode": mode,
                "cpu_one_core_percent": distribution([s["cpu_one_core_percent"] for s in samples]),
                "footprint_mib": distribution([s["footprint_bytes"] / 2**20 for s in samples]),
                "rss_mib": distribution([s["rss_bytes"] / 2**20 for s in samples]),
                "dart_heap_mib": distribution([s["dart"]["heapUsage"] / 2**20 for s in samples]),
                "dart_external_mib": distribution([s["dart"]["externalUsage"] / 2**20 for s in samples]),
                "flutter_frames": len(frames),
                "native_scheduled_frames": status["nativeScheduler"]["scheduledFrames"] - native_start,
                "native_scheduled_fps": (status["nativeScheduler"]["scheduledFrames"] - native_start)
                    / (now - start),
                "native_active_samples": sum(s["native_scheduler"]["active"]
                    and not s["native_scheduler"]["paused"] for s in samples),
                "engine_raster_events": sum(e.get("name") == "CompositorContext::ScopedFrame::Raster"
                    and e.get("ph") in ("B", "X") for e in trace["traceEvents"]),
                "build_ms": distribution([f["buildUs"] / 1000 for f in frames]),
                "raster_ms": distribution([f["rasterUs"] / 1000 for f in frames]),
                "flutter_frames_over_16_67ms": sum(max(f["buildUs"], f["rasterUs"]) > 16667 for f in frames),
                "vm_time_origin_us": origin, "vm_time_end_us": end, "status": status}
            results.append({"summary": summary, "samples": samples, "frames": frames,
                            "process_memory": process_memory})
            (args.output / "results.json").write_text(json.dumps(
                {"metadata": metadata, "results": results}, indent=2))
            print(json.dumps(summary), flush=True)
        # Native symbolization allocates heavily in the app's service isolate.
        # Export only after the last memory sample, so it cannot inflate later phases.
        cpu = rpc("getCpuSamples", isolateId=isolate, timeOriginMicros=profile_origin,
                  timeExtentMicros=end-profile_origin)
        with gzip.open(args.output / "cpu-samples.json.gz", "wt") as output:
            json.dump(cpu, output)
    finally:
        control(mode="hidden", record=False)
        rpc("setVMTimelineFlags", recordedStreams="[]")


if __name__ == "__main__":
    main()
