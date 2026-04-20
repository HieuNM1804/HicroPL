import os
import sys
import time
import os.path as osp
import builtins
from contextlib import contextmanager

from .tools import mkdir_if_missing

__all__ = [
    "Logger",
    "setup_logger",
    "suppress_print",
    "restore_print",
    "temporary_restore_print",
]

_ORIGINAL_PRINT = builtins.print
_PRINT_SUPPRESSED = False


class Logger:
    """Write console output to external text file.

    Imported from `<https://github.com/Cysu/open-reid/blob/master/reid/utils/logging.py>`_

    Args:
        fpath (str): directory to save logging file.

    Examples::
       >>> import sys
       >>> import os.path as osp
       >>> save_dir = 'output/experiment-1'
       >>> log_name = 'train.log'
       >>> sys.stdout = Logger(osp.join(save_dir, log_name))
    """

    def __init__(self, fpath=None):
        self.console = sys.stdout
        self.file = None
        if fpath is not None:
            mkdir_if_missing(osp.dirname(fpath))
            self.file = open(fpath, "w")

    def __del__(self):
        self.close()

    def __enter__(self):
        pass

    def __exit__(self, *args):
        self.close()

    def write(self, msg):
        self.console.write(msg)
        if self.file is not None:
            self.file.write(msg)

    def flush(self):
        self.console.flush()
        if self.file is not None:
            self.file.flush()
            os.fsync(self.file.fileno())

    def close(self):
        self.console.close()
        if self.file is not None:
            self.file.close()


def setup_logger(output=None):
    if output is None:
        return

    if output.endswith(".txt") or output.endswith(".log"):
        fpath = output
    else:
        fpath = osp.join(output, "log.txt")

    if osp.exists(fpath):
        # make sure the existing log file is not over-written
        fpath += time.strftime("-%Y-%m-%d-%H-%M-%S")

    sys.stdout = Logger(fpath)


def suppress_print():
    global _PRINT_SUPPRESSED

    if _PRINT_SUPPRESSED:
        return

    builtins.print = lambda *args, **kwargs: None
    _PRINT_SUPPRESSED = True


def restore_print():
    global _PRINT_SUPPRESSED

    builtins.print = _ORIGINAL_PRINT
    _PRINT_SUPPRESSED = False


@contextmanager
def temporary_restore_print():
    was_suppressed = _PRINT_SUPPRESSED

    if was_suppressed:
        restore_print()

    try:
        yield
    finally:
        if was_suppressed:
            suppress_print()
