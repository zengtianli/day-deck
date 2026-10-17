"""Keep simulator catalog timeouts in the original queue's deferred state."""
from contextlib import contextmanager
import subprocess


@contextmanager
def defer_catalog_timeouts(lane):
    # The shared runner currently turns TimeoutExpired into a plain LaneError.
    # Adapt only simctl list, at the command boundary; rc errors and product
    # assertions retain their original failure semantics. No retry or gate bypass.
    original = lane.simctl

    def simctl(*args, **kwargs):
        try:
            return original(*args, **kwargs)
        except (lane.LaneError, subprocess.TimeoutExpired) as exc:
            command = ["xcrun", "simctl", *args]
            expected = f"{' '.join(map(str, command[:4]))} 超过 {kwargs.get('timeout', 120)}s"
            if args and args[0] == "list" and (
                    isinstance(exc, subprocess.TimeoutExpired) or str(exc) == expected):
                raise lane.Busy("模拟器目录查询超时，交回原队列，未生成通过证据") from exc
            raise

    lane.simctl = simctl
    try:
        yield
    finally:
        lane.simctl = original
