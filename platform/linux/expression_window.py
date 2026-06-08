#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""rt-claw Expression Window — display expression GIFs on Raspberry Pi desktop.

Requires: python3-tk python3-pil python3-pil.imagetk
Install:  sudo apt install python3-tk python3-pil python3-pil.imagetk
"""

import sys
import os
import socket
import threading
import argparse

_MISSING_DEPS = []

try:
    import tkinter as tk
except ImportError:
    _MISSING_DEPS.append("python3-tk")
    tk = None

try:
    from PIL import Image, ImageSequence
except ImportError:
    _MISSING_DEPS.append("python3-pil")
    Image = None
    ImageSequence = None

try:
    from PIL import ImageTk
except ImportError:
    _MISSING_DEPS.append("python3-pil.imagetk")
    ImageTk = None

try:
    from PIL.Image import Resampling
    LANCZOS = Resampling.LANCZOS
except (ImportError, AttributeError):
    try:
        LANCZOS = Image.LANCZOS
    except AttributeError:
        LANCZOS = None


class ExpressionWindow:
    def __init__(self, assets_dir, ipc_path, window_w=240, window_h=240):
        self.assets_dir = assets_dir
        self.ipc_path = ipc_path
        self.window_w = window_w
        self.window_h = window_h
        self.current_expression = "idle"
        self.gif_image = None
        self.gif_durations = []
        self.frame_index = 0

        self.root = tk.Tk()
        self.root.title("rt-claw Expression")
        self.root.geometry(f"{window_w}x{window_h}")
        self.root.resizable(False, False)

        self.label = tk.Label(self.root, bg='black')
        self.label.pack(expand=True, fill='both')

        self.load_expression("idle")

        self.animate()

        self.ipc_thread = threading.Thread(target=self.ipc_listener,
                                           daemon=True)
        self.ipc_thread.start()

    def _decode_current_frame(self):
        """Decode only the current frame to a PhotoImage (lazy loading)."""
        if not self.gif_image:
            return None
        try:
            self.gif_image.seek(self.frame_index)
            frame = self.gif_image.convert('RGBA')
            frame = frame.resize((self.window_w, self.window_h), LANCZOS)
            return ImageTk.PhotoImage(frame)
        except Exception:
            return None

    def load_expression(self, name):
        """Load GIF file for the named expression (lazy frame decode)."""
        path = os.path.join(self.assets_dir, f"{name}.gif")
        if not os.path.exists(path):
            print(f"[expr_win] GIF not found: {path}", flush=True)
            return False

        try:
            if self.gif_image:
                self.gif_image.close()

            self.gif_image = Image.open(path)
            self.gif_durations = []
            for frame in ImageSequence.Iterator(self.gif_image):
                self.gif_durations.append(
                    frame.info.get('duration', 100))

            self.frame_index = 0
            self.current_expression = name

            photo = self._decode_current_frame()
            if photo:
                self._current_photo = photo
                self.label.configure(image=photo)

            print(f"[expr_win] loaded {name} "
                  f"({len(self.gif_durations)} frames)", flush=True)
            return True

        except Exception as e:
            print(f"[expr_win] Failed to load GIF: {e}", flush=True)
            return False

    def animate(self):
        """Animate GIF frames (lazy decode per frame)."""
        if self.gif_image and self.gif_durations:
            photo = self._decode_current_frame()
            if photo:
                self._current_photo = photo
                self.label.configure(image=photo)
            self.frame_index = (self.frame_index + 1) % len(self.gif_durations)
            delay = self.gif_durations[self.frame_index]
            self.root.after(delay, self.animate)

    def ipc_listener(self):
        """Listen on Unix domain socket for expression commands."""
        if os.path.exists(self.ipc_path):
            os.unlink(self.ipc_path)

        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(self.ipc_path)
        sock.listen(5)
        os.chmod(self.ipc_path, 0o666)

        print(f"[expr_win] IPC listening on {self.ipc_path}",
              flush=True)

        while True:
            try:
                conn, _ = sock.accept()
                with conn:
                    data = conn.recv(64).decode('utf-8').strip()
                    if data.startswith('set '):
                        expr = data[4:].strip()
                        print(f"[expr_win] IPC command: set {expr}",
                              flush=True)
                        self.root.after(0,
                                        lambda e=expr: self.load_expression(e))
            except Exception as e:
                print(f"IPC error: {e}")

    def run(self):
        self.root.mainloop()


def main():
    parser = argparse.ArgumentParser(
        description='rt-claw Expression Window')
    parser.add_argument('--assets', default='assets/expressions',
                        help='Path to expression GIF assets')
    parser.add_argument('--ipc', default='/tmp/rtclaw-expression.sock',
                        help='Unix domain socket path')
    parser.add_argument('--width', type=int, default=240,
                        help='Window width in pixels (default: 240)')
    parser.add_argument('--height', type=int, default=240,
                        help='Window height in pixels (default: 240)')

    args = parser.parse_args()

    if not os.path.exists(args.assets):
        print(f"[expr_win] Assets directory not found: {args.assets}",
              flush=True)
        sys.exit(1)

    print(f"[expr_win] starting  assets={args.assets} "
          f"ipc={args.ipc}  size={args.width}x{args.height}",
          flush=True)

    window = ExpressionWindow(args.assets, args.ipc,
                              args.width, args.height)
    window.run()


if __name__ == '__main__':
    main()
