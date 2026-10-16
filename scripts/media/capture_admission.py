"""Recording admission delegates machine contention to the original simulator lane.

Call after SDK builds, before boot/recording. This is not a build admission gate.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
import app_sop
import sim_lane


def check(in_use):
    reasons = []
    if not in_use:
        observed = app_sop.sh(["ioreg", "-c", "IOHIDSystem"]).stdout
        match = re.search(r'"HIDIdleTime"\s*=\s*(\d+)', observed)
        idle = int(match.group(1)) // 1_000_000_000 if match else None
        if idle is None or idle < 600:
            reasons.append(f"用户 {idle if idle is not None else '?'} 秒前有操作")
    busy = sim_lane.machine_busy(sim_lane.max_load_default())
    memory = sim_lane.memory_tight()
    builds = sim_lane.heavy_builds()
    if busy:
        reasons.append(busy)
    if memory:
        reasons.append(memory)
    if builds:
        reasons.append("有构建在跑")
    return not reasons, "；".join(reasons) or "原sim_lane CPU/内存/构建安静门通过"
