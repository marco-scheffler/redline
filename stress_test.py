#!/usr/bin/env python3
"""
MacBook Stress Test
Comprehensive system stress testing tool with native macOS design.
Tests: CPU (multi-core), GPU (Metal), RAM, Disk I/O
"""

import tkinter as tk
import multiprocessing as mp
import threading
import time
import os
import sys
import math
import re
import tempfile
import platform
import subprocess
import fcntl
from pathlib import Path
from datetime import datetime

try:
    import psutil
except ImportError:
    psutil = None

# ═══════════════════════════════════════════════════════════
# Apple Design System Colors (Dark Mode)
# ═══════════════════════════════════════════════════════════

A = {
    'window':       '#0f0f0f',
    'card':         '#1c1c1e',
    'card_elevated':'#2c2c2e',
    'fill':         '#38383a',
    'fill_sec':     '#48484a',
    'separator':    '#38383a',
    'outline':      '#303033',
    'label':        '#ffffff',
    'label_sec':    '#98989d',
    'label_ter':    '#636366',
    'blue':         '#0a84ff',
    'green':        '#30d158',
    'red':          '#ff453a',
    'orange':       '#ff9f0a',
    'purple':       '#bf5af2',
    'teal':         '#64d2ff',
    'bar_bg':       '#38383a',
}

FONT       = 'Helvetica Neue'
FONT_MONO  = 'Menlo'

APP_DIR    = Path(__file__).parent
GPU_BINARY = APP_DIR / ".gpu_stress_bin"
GPU_SOURCE = APP_DIR / ".gpu_stress.swift"

SWIFT_GPU_CODE = r'''
import Foundation
import Metal

signal(SIGTERM) { _ in exit(0) }
signal(SIGINT) { _ in exit(0) }

guard let device = MTLCreateSystemDefaultDevice() else {
    print("ERROR|No Metal GPU device found"); fflush(stdout); exit(1)
}
guard let queue = device.makeCommandQueue() else {
    print("ERROR|Could not create command queue"); fflush(stdout); exit(1)
}

let shaderSource = """
#include <metal_stdlib>
using namespace metal;
kernel void stress(device float *data [[buffer(0)]], uint id [[thread_position_in_grid]]) {
    float x = data[id];
    for (int i = 0; i < 5000; i++) {
        x = sin(x) * cos(x) + sqrt(abs(x) + 1.0);
        x = x * x - floor(x) + fract(x * 3.14159);
        x = log2(abs(x) + 1.0) * exp2(fract(x));
    }
    data[id] = x;
}
"""

let bufferMB = CommandLine.arguments.count > 1 ? (Int(CommandLine.arguments[1]) ?? 256) : 256
let elementCount = bufferMB * 1024 * 1024 / MemoryLayout<Float>.size

do {
    let library = try device.makeLibrary(source: shaderSource, options: nil)
    guard let function = library.makeFunction(name: "stress") else {
        print("ERROR|Could not find compute function"); fflush(stdout); exit(1)
    }
    let pipeline = try device.makeComputePipelineState(function: function)
    guard let buffer = device.makeBuffer(length: elementCount * MemoryLayout<Float>.size,
                                          options: .storageModeShared) else {
        print("ERROR|Could not create Metal buffer"); fflush(stdout); exit(1)
    }
    let ptr = buffer.contents().bindMemory(to: Float.self, capacity: elementCount)
    for i in 0..<elementCount { ptr[i] = Float.random(in: -1.0...1.0) }
    print("GPU_READY|\(device.name)|\(bufferMB)"); fflush(stdout)
    var iterations = 0; let startTime = Date()
    while true {
        guard let cmdBuf = queue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else { continue }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        let tpg = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        let numGroups = (elementCount + tpg - 1) / tpg
        encoder.dispatchThreadgroups(MTLSize(width: numGroups, height: 1, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: tpg, height: 1, depth: 1))
        encoder.endEncoding(); cmdBuf.commit(); cmdBuf.waitUntilCompleted()
        iterations += 1
        if iterations % 5 == 0 {
            let elapsed = Date().timeIntervalSince(startTime)
            print("GPU_STAT|\(iterations)|\(String(format: "%.1f", Double(iterations)/elapsed))")
            fflush(stdout)
        }
    }
} catch { print("ERROR|\(error)"); fflush(stdout); exit(1) }
'''


# ═══════════════════════════════════════════════════════════
# CPU Stress Worker
# ═══════════════════════════════════════════════════════════

def cpu_stress_worker(stop_event, mode):
    x, n = 1.5, (1 << 63) - 1
    try:
        while not stop_event.is_set():
            if mode == "float":
                for _ in range(50000):
                    x = math.sin(x) * math.cos(x) + math.sqrt(abs(x) + 1.0)
                    x = math.log(abs(x) + 1.0) + math.atan2(x, 1.0)
                    x = math.exp(min(abs(x), 10.0)) - math.exp(min(abs(x), 9.0))
                    if abs(x) > 1e15: x = 1.5
            elif mode == "integer":
                for _ in range(50000):
                    n = (n * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
                    n ^= n >> 33
                    n = (n * 0xFF51AFD7ED558CCD) & ((1 << 64) - 1)
                    n ^= n >> 33
                    n = (n * 0xC4CEB9FE1A85EC53) & ((1 << 64) - 1)
            else:
                for _ in range(25000):
                    x = math.sin(x) * math.cos(x) + math.sqrt(abs(x) + 1.0)
                    n = (n * 6364136223846793005 + 1) & ((1 << 64) - 1)
                    x += (n & 0xFFFF) / 65536.0
                    n ^= n >> 33
                    if abs(x) > 1e15: x = 1.5
    except KeyboardInterrupt:
        pass


# ═══════════════════════════════════════════════════════════
# System Info
# ═══════════════════════════════════════════════════════════

def get_system_info():
    info = {}
    try:
        info["cpu"] = subprocess.check_output(
            ["sysctl", "-n", "machdep.cpu.brand_string"], stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        info["cpu"] = platform.processor() or "Unknown"
    info["cores_physical"] = psutil.cpu_count(logical=False) if psutil else mp.cpu_count()
    info["cores_logical"] = psutil.cpu_count(logical=True) if psutil else mp.cpu_count()
    try:
        info["p_cores"] = int(subprocess.check_output(
            ["sysctl", "-n", "hw.perflevel0.logicalcpu"], stderr=subprocess.DEVNULL).decode().strip())
        info["e_cores"] = int(subprocess.check_output(
            ["sysctl", "-n", "hw.perflevel1.logicalcpu"], stderr=subprocess.DEVNULL).decode().strip())
    except Exception:
        info["p_cores"] = info["e_cores"] = None
    if psutil:
        mem = psutil.virtual_memory()
        info["ram_total"], info["ram_available"] = mem.total, mem.available
    else:
        try:
            t = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], stderr=subprocess.DEVNULL).decode().strip())
            info["ram_total"], info["ram_available"] = t, t // 2
        except Exception:
            info["ram_total"] = info["ram_available"] = 0
    info["os_version"] = platform.mac_ver()[0]
    try:
        info["model"] = subprocess.check_output(
            ["sysctl", "-n", "hw.model"], stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        info["model"] = "Mac"
    return info


# ═══════════════════════════════════════════════════════════
# Drawing Helpers
# ═══════════════════════════════════════════════════════════

def _rrect(canvas, x1, y1, x2, y2, r, **kw):
    """Draw a rounded rectangle using smooth polygon."""
    x1, y1, x2, y2, r = float(x1), float(y1), float(x2), float(y2), float(r)
    r = min(r, (x2 - x1) / 2, (y2 - y1) / 2)
    if r < 1:
        return canvas.create_rectangle(x1, y1, x2, y2, **kw)
    pts = [
        x1 + r, y1, x1 + r, y1, x2 - r, y1, x2 - r, y1,
        x2, y1, x2, y1 + r, x2, y1 + r,
        x2, y2 - r, x2, y2 - r, x2, y2,
        x2 - r, y2, x2 - r, y2, x1 + r, y2, x1 + r, y2,
        x1, y2, x1, y2 - r, x1, y2 - r,
        x1, y1 + r, x1, y1 + r, x1, y1,
    ]
    return canvas.create_polygon(pts, smooth=True, **kw)


def _lighten(hex_color, amount):
    r, g, b = int(hex_color[1:3], 16), int(hex_color[3:5], 16), int(hex_color[5:7], 16)
    r = min(255, int(r + (255 - r) * amount))
    g = min(255, int(g + (255 - g) * amount))
    b = min(255, int(b + (255 - b) * amount))
    return f'#{r:02x}{g:02x}{b:02x}'


def _dim(hex_color, amount):
    r, g, b = int(hex_color[1:3], 16), int(hex_color[3:5], 16), int(hex_color[5:7], 16)
    return f'#{int(r*amount):02x}{int(g*amount):02x}{int(b*amount):02x}'


def _clean_cpu(name):
    """Shorten verbose CPU brand strings (esp. Intel) for header chips."""
    name = name.replace('(R)', '').replace('(TM)', '').replace('CPU', '')
    name = re.sub(r'\s*@.*$', '', name)          # drop "@ 2.40GHz"
    name = re.sub(r'\d+-Core Processor', '', name)
    return ' '.join(name.split()) or 'Processor'


# ═══════════════════════════════════════════════════════════
# Custom Widgets – Apple Design Language
# ═══════════════════════════════════════════════════════════

class RoundedCard(tk.Canvas):
    """Card with true rounded corners, auto-sizing to content."""

    def __init__(self, parent, radius=14, bg=None, pad_x=10, pad_y=8):
        pbg = parent.cget('bg')
        super().__init__(parent, highlightthickness=0, bg=pbg, bd=0)
        self._r = radius
        self._cbg = bg or A['card']
        self.inner = tk.Frame(self, bg=self._cbg, padx=pad_x, pady=pad_y)
        self._win = self.create_window(radius, radius, window=self.inner, anchor='nw')
        self.bind('<Configure>', self._on_resize)
        self.inner.bind('<Configure>', self._fit)

    def _on_resize(self, event):
        self.itemconfig(self._win, width=max(1, event.width - 2 * self._r))
        self._draw(event.width, event.height)

    def _fit(self, event):
        needed = event.height + 2 * self._r
        if abs(needed - self.winfo_height()) > 2:
            self.configure(height=needed)

    def _draw(self, w=None, h=None):
        w, h = w or self.winfo_width(), h or self.winfo_height()
        self.delete('bg')
        if w > 2 and h > 2:
            _rrect(self, 1, 1, w - 1, h - 1, self._r, fill=self._cbg,
                   outline=A['outline'], width=1, tags='bg')
            # subtle top highlight for a soft "glass card" elevation
            self.create_line(self._r, 2, w - self._r, 2,
                             fill=_lighten(self._cbg, 0.06), tags='bg')
            self.tag_lower('bg')


class IconTile(tk.Canvas):
    """iOS-style tinted rounded-square icon with a vector glyph.

    Sits muted/tinted while idle and brightens into its accent colour
    (with a soft pulsing glow) while the matching test is running.
    Drop-in replacement for the old StatusDot: same activate()/deactivate() API.
    """

    _PAD = 4  # margin reserved around the tile so the active glow can bleed out

    def __init__(self, parent, glyph, color, size=26):
        dim = size + 2 * self._PAD
        super().__init__(parent, width=dim, height=dim,
                         highlightthickness=0, bg=parent.cget('bg'), bd=0)
        self._glyph = glyph
        self._color = color
        self._s = size
        self._active = False
        self._bright = False
        self._draw()

    def activate(self, color=None):
        if color:
            self._color = color
        if not self._active:
            self._active = True
            self._tick()

    def deactivate(self):
        self._active = False
        self._draw()

    def _tick(self):
        if not self._active:
            return self._draw()
        self._bright = not self._bright
        self._draw()
        self.after(900, self._tick)

    def _draw(self):
        self.delete('all')
        o, s, col = self._PAD, self._s, self._color
        x0, y0, x1, y1 = o, o, o + s, o + s
        if self._active:
            gr = 3 if self._bright else 1
            _rrect(self, x0 - gr, y0 - gr, x1 + gr, y1 + gr, 8 + gr,
                   fill=_dim(col, 0.45), outline='')
            _rrect(self, x0, y0, x1, y1, 8, fill=col, outline='')
            glyph_col = '#ffffff'
        else:
            _rrect(self, x0, y0, x1, y1, 8,
                   fill=_dim(col, 0.30), outline=_dim(col, 0.55))
            glyph_col = _lighten(col, 0.08)
        self._draw_glyph(x0, y0, x1, y1, glyph_col)

    def _draw_glyph(self, x0, y0, x1, y1, c):
        gp = 6
        ax0, ay0, ax1, ay1 = x0 + gp, y0 + gp, x1 - gp, y1 - gp
        cx, cy = (ax0 + ax1) / 2, (ay0 + ay1) / 2
        g, lw = self._glyph, 2

        if g == 'cpu':  # processor: chip body + pins
            self.create_rectangle(ax0, ay0, ax1, ay1, outline=c, width=lw)
            m = 2.5
            self.create_rectangle(ax0 + m, ay0 + m, ax1 - m, ay1 - m, outline=c, width=1)
            for fx in (0.33, 0.66):
                px = ax0 + (ax1 - ax0) * fx
                self.create_line(px, ay0 - 2.5, px, ay0, fill=c, width=lw)
                self.create_line(px, ay1, px, ay1 + 2.5, fill=c, width=lw)
            for fy in (0.33, 0.66):
                py = ay0 + (ay1 - ay0) * fy
                self.create_line(ax0 - 2.5, py, ax0, py, fill=c, width=lw)
                self.create_line(ax1, py, ax1 + 2.5, py, fill=c, width=lw)
        elif g == 'gpu':  # graphics: 4-point sparkle
            R = (ax1 - ax0) / 2
            r = R * 0.4
            self.create_polygon(
                cx, cy - R, cx + r, cy - r, cx + R, cy, cx + r, cy + r,
                cx, cy + R, cx - r, cy + r, cx - R, cy, cx - r, cy - r,
                fill=c, outline='')
        elif g == 'memory':  # RAM module
            self.create_rectangle(ax0, ay0 + 1, ax1, ay1 - 2, outline=c, width=lw)
            for fx in (0.25, 0.5, 0.75):
                px = ax0 + (ax1 - ax0) * fx
                self.create_line(px, ay0 + 1, px, ay1 - 2, fill=c, width=1)
            for fx in (0.2, 0.8):
                px = ax0 + (ax1 - ax0) * fx
                self.create_line(px, ay1 - 2, px, ay1 + 1, fill=c, width=lw)
        elif g == 'disk':  # storage cylinder
            eh = (ay1 - ay0) * 0.32
            self.create_oval(ax0, ay0, ax1, ay0 + eh, outline=c, width=lw)
            self.create_line(ax0, ay0 + eh / 2, ax0, ay1 - eh / 2, fill=c, width=lw)
            self.create_line(ax1, ay0 + eh / 2, ax1, ay1 - eh / 2, fill=c, width=lw)
            self.create_arc(ax0, ay1 - eh, ax1, ay1, start=180, extent=180,
                            style='arc', outline=c, width=lw)
        elif g == 'monitor':  # activity pulse
            w = ax1 - ax0
            self.create_line(
                ax0, cy, ax0 + w * 0.22, cy, ax0 + w * 0.38, ay0,
                ax0 + w * 0.55, ay1, ax0 + w * 0.72, cy, ax1, cy,
                fill=c, width=lw, capstyle='round', joinstyle='round')


class AppleBar(tk.Canvas):
    """Rounded progress bar."""

    def __init__(self, parent, height=6, color=A['blue'], **kw):
        super().__init__(parent, height=height, highlightthickness=0,
                         bg=parent.cget('bg'), bd=0, **kw)
        self._color = color
        self._val = 0
        self._bar_h = height
        self.bind('<Configure>', lambda e: self._draw())

    def set(self, val):
        self._val = max(0.0, min(100.0, val))
        self._draw()

    def _draw(self):
        self.delete('all')
        w = self.winfo_width() or 200
        h = self._bar_h
        r = h // 2
        _rrect(self, 0, 0, w, h, r, fill=A['bar_bg'], outline='')
        if self._val > 0:
            fw = max(h, int(w * self._val / 100))
            _rrect(self, 0, 0, fw, h, r, fill=self._color, outline='')
            # specular highlight along the top for a glossy fill
            if h >= 6 and fw > 2:
                _rrect(self, 1, 1, fw - 1, h / 2, r,
                       fill=_lighten(self._color, 0.22), outline='')


class AppleButton(tk.Canvas):
    """Rounded pill button with hover and press states."""

    def __init__(self, parent, text, command, color=A['blue'], style='filled',
                 font_size=12, pad_x=18, pad_y=7):
        self._cmd = command
        self._color = color
        self._style = style  # 'filled' or 'tinted'
        self._enabled = True
        self._hover = False
        self._text = text
        self._font = (FONT, font_size, 'bold') if style == 'filled' else (FONT, font_size)

        tmp = tk.Label(parent, text=text, font=self._font)
        tmp.update_idletasks()
        tw = int(tmp.winfo_reqwidth())
        th = int(tmp.winfo_reqheight())
        tmp.destroy()
        self._bw = tw + 2 * pad_x
        self._bh = th + 2 * pad_y

        pbg = parent.cget('bg')
        super().__init__(parent, width=self._bw, height=self._bh,
                         highlightthickness=0, bg=pbg, bd=0, cursor='hand2')
        self._pbg = pbg
        self._draw()
        self.bind('<Button-1>', self._press)
        self.bind('<ButtonRelease-1>', self._release)
        self.bind('<Enter>', lambda e: self._set_hover(True))
        self.bind('<Leave>', lambda e: self._set_hover(False))

    def _set_hover(self, val):
        self._hover = val
        self._draw()

    def _draw(self, pressed=False):
        self.delete('all')
        w, h = self._bw, self._bh
        r = h // 2

        if self._style == 'filled':
            bg = self._color
            fg = '#ffffff'
            if not self._enabled:
                bg = _dim(bg, 0.35)
                fg = A['label_ter']
            elif pressed:
                bg = _dim(bg, 0.6)
            elif self._hover:
                bg = _lighten(bg, 0.12)
        else:  # tinted
            bg = _dim(self._color, 0.2)
            fg = self._color
            if not self._enabled:
                bg = A['fill']
                fg = A['label_ter']
            elif pressed:
                bg = _dim(self._color, 0.3)
            elif self._hover:
                bg = _dim(self._color, 0.25)

        _rrect(self, 0, 0, w, h, r, fill=bg, outline='')
        self.create_text(w // 2, h // 2, text=self._text, fill=fg, font=self._font)

    def _press(self, e):
        if self._enabled:
            self._draw(pressed=True)

    def _release(self, e):
        self._draw()
        if self._enabled and 0 <= e.x <= self._bw and 0 <= e.y <= self._bh:
            self._cmd()

    def set_enabled(self, val):
        self._enabled = val
        self.configure(cursor='hand2' if val else 'arrow')
        self._draw()


class SegmentedControl(tk.Canvas):
    """Apple-style segmented control."""

    def __init__(self, parent, segments, variable, height=30, font_size=11):
        self._segs = segments  # [(label, value), ...]
        self._var = variable
        self._font = (FONT, font_size)
        self._seg_h = height
        self._seg_r = 8

        tmp = tk.Label(parent, font=self._font)
        self._sw = []
        for label, _ in segments:
            tmp.config(text=label)
            tmp.update_idletasks()
            self._sw.append(int(tmp.winfo_reqwidth()) + 28)
        tmp.destroy()
        total_w = sum(self._sw) + 4

        pbg = parent.cget('bg')
        super().__init__(parent, width=total_w, height=height,
                         highlightthickness=0, bg=pbg, bd=0, cursor='hand2')
        self._seg_tw = total_w
        self._draw()
        self.bind('<Button-1>', self._click)
        variable.trace_add('write', lambda *_: self._draw())

    def _draw(self):
        self.delete('all')
        w, h, r = self._seg_tw, self._seg_h, self._seg_r
        _rrect(self, 0, 0, w, h, r, fill=A['fill'], outline='')
        cur = self._var.get()
        x = 2
        for i, (label, val) in enumerate(self._segs):
            sw = self._sw[i]
            if val == cur:
                _rrect(self, x, 2, x + sw, h - 2, r - 1,
                       fill=A['card_elevated'], outline='')
            fg = A['label'] if val == cur else A['label_sec']
            self.create_text(x + sw // 2, h // 2, text=label, fill=fg, font=self._font)

            # Separator
            if i < len(self._segs) - 1 and val != cur:
                nx_val = self._segs[i + 1][1]
                if nx_val != cur:
                    self.create_line(x + sw, 6, x + sw, h - 6, fill=A['separator'], width=1)
            x += sw

    def _click(self, event):
        x = 2
        for i, (_, val) in enumerate(self._segs):
            if x <= event.x < x + self._sw[i]:
                self._var.set(val)
                return
            x += self._sw[i]


class InfoChip(tk.Canvas):
    """Small rounded info pill with an optional leading colour dot."""

    def __init__(self, parent, text, dot=None, font_size=11):
        font = (FONT, font_size)
        probe = tk.Label(parent, text=text, font=font)
        probe.update_idletasks()
        tw, th = int(probe.winfo_reqwidth()), int(probe.winfo_reqheight())
        probe.destroy()
        lead = 14 if dot else 0
        padx = 12
        w, h = tw + 2 * padx + lead, th + 10
        super().__init__(parent, width=w, height=h,
                         highlightthickness=0, bg=parent.cget('bg'), bd=0)
        _rrect(self, 1, 1, w - 1, h - 1, h // 2,
               fill=A['card'], outline=A['outline'])
        x = padx
        if dot:
            cyc = h // 2
            _rrect(self, x, cyc - 3, x + 6, cyc + 3, 3, fill=dot, outline='')
            x += lead - 2
        self.create_text(x, h // 2, text=text, anchor='w',
                         fill=A['label_sec'], font=font)


class AppleSlider(tk.Canvas):
    """Apple-style horizontal slider: rounded track, accent fill, white knob.

    Snaps to integer steps and stays bound to an IntVar (click or drag to set).
    """

    def __init__(self, parent, from_, to, variable, color=A['blue'],
                 width=190, height=28):
        super().__init__(parent, width=width, height=height,
                         highlightthickness=0, bg=parent.cget('bg'),
                         bd=0, cursor='hand2')
        self._min, self._max = from_, to
        self._var = variable
        self._color = color
        self._cw, self._ch = width, height
        self._kr = 9
        self._pad = self._kr + 2
        self.bind('<Button-1>', self._on_drag)
        self.bind('<B1-Motion>', self._on_drag)
        self._var.trace_add('write', lambda *_: self._draw())
        self._draw()

    def _track(self):
        return self._pad, self._cw - self._pad, self._ch // 2

    def _val_x(self, v):
        x0, x1, _ = self._track()
        span = self._max - self._min
        frac = (v - self._min) / span if span else 0
        return x0 + frac * (x1 - x0)

    def _on_drag(self, e):
        x0, x1, _ = self._track()
        frac = max(0.0, min(1.0, (e.x - x0) / (x1 - x0))) if x1 > x0 else 0
        v = int(round(self._min + frac * (self._max - self._min)))
        v = max(self._min, min(self._max, v))
        if v != self._var.get():
            self._var.set(v)
        else:
            self._draw()

    def _draw(self):
        self.delete('all')
        x0, x1, cy = self._track()
        r = 2
        _rrect(self, x0, cy - r, x1, cy + r, r, fill=A['fill'], outline='')
        kx = self._val_x(self._var.get())
        _rrect(self, x0, cy - r, max(x0 + 1, kx), cy + r, r,
               fill=self._color, outline='')
        kr = self._kr
        self.create_oval(kx - kr, cy - kr + 1, kx + kr, cy + kr + 1,
                         fill=_dim(A['window'], 0.4), outline='')   # soft shadow
        self.create_oval(kx - kr, cy - kr, kx + kr, cy + kr,
                         fill='#ffffff', outline='#c7c7cc')


# ═══════════════════════════════════════════════════════════
# Backend Managers (GPU, RAM, Disk)
# ═══════════════════════════════════════════════════════════

class GPUStressManager:
    def __init__(self, log_cb=None):
        self.process = None
        self.log = log_cb or (lambda m: None)
        self.running = False
        self.gpu_name = ""
        self.iter_rate = 0.0
        self._compiled = False

    def compile(self):
        if self._compiled and GPU_BINARY.exists():
            return True
        try:
            subprocess.run(["swiftc", "--version"], capture_output=True, timeout=5)
        except Exception:
            self.log("swiftc not found – install Xcode CLI tools: xcode-select --install")
            return False
        self.log("Compiling GPU binary...")
        GPU_SOURCE.write_text(SWIFT_GPU_CODE)
        try:
            r = subprocess.run(["swiftc", "-O", "-o", str(GPU_BINARY), str(GPU_SOURCE)],
                               capture_output=True, text=True, timeout=120)
            if r.returncode != 0:
                self.log(f"Compile error: {r.stderr[:200]}")
                return False
            self._compiled = True
            self.log("GPU binary compiled")
            return True
        except Exception as e:
            self.log(f"Compile failed: {e}")
            return False

    def start(self, buffer_mb=256):
        if self.running or not self.compile():
            return
        self.running = True
        try:
            self.process = subprocess.Popen(
                [str(GPU_BINARY), str(buffer_mb)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
            threading.Thread(target=self._read, daemon=True).start()
        except Exception as e:
            self.log(f"GPU start failed: {e}")
            self.running = False

    def _read(self):
        try:
            for line in self.process.stdout:
                line = line.strip()
                if line.startswith("GPU_READY|"):
                    p = line.split("|")
                    self.gpu_name = p[1] if len(p) > 1 else ""
                    self.log(f"GPU active: {self.gpu_name} ({p[2] if len(p)>2 else '?'} MB)")
                elif line.startswith("GPU_STAT|"):
                    p = line.split("|")
                    if len(p) >= 3:
                        self.iter_rate = float(p[2])
                elif line.startswith("ERROR|"):
                    self.log(f"GPU error: {line[6:]}")
        except Exception:
            pass

    def stop(self):
        if not self.running:
            return
        self.running = False
        if self.process:
            try:
                self.process.terminate()
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
            except Exception:
                pass
            self.process = None
        self.iter_rate = 0.0


class RAMStressManager:
    def __init__(self, log_cb=None):
        self.log = log_cb or (lambda m: None)
        self.running = False
        self._stop = threading.Event()
        self._alloc_mb = 0
        self._blocks = []

    def start(self, mb):
        if self.running:
            return
        self._stop.clear()
        self.running = True
        threading.Thread(target=self._run, args=(mb,), daemon=True).start()

    def _run(self, mb):
        chunk = 64 * 1024 * 1024
        target = mb * 1024 * 1024
        self._alloc_mb = 0
        self._blocks = []
        self.log(f"RAM: allocating {mb} MB...")
        try:
            while not self._stop.is_set() and self._alloc_mb * 1024 * 1024 < target:
                sz = min(chunk, target - self._alloc_mb * 1024 * 1024)
                self._blocks.append(bytearray(os.urandom(sz)))
                self._alloc_mb = sum(len(b) for b in self._blocks) // (1024 * 1024)
                time.sleep(0.05)
            self.log(f"RAM: {self._alloc_mb} MB allocated")
            while not self._stop.is_set():
                for b in self._blocks:
                    if self._stop.is_set():
                        break
                    for i in range(0, len(b), 4096):
                        b[i] = (b[i] + 1) & 0xFF
                time.sleep(0.5)
        except MemoryError:
            self.log(f"RAM: OOM at {self._alloc_mb} MB")

    @property
    def allocated_mb(self):
        return self._alloc_mb

    def stop(self):
        if not self.running:
            return
        self._stop.set()
        self.running = False
        time.sleep(0.1)
        self._blocks.clear()
        self._alloc_mb = 0
        self.log("RAM: released")


class DiskStressManager:
    def __init__(self, log_cb=None):
        self.log = log_cb or (lambda m: None)
        self.running = False
        self._stop = threading.Event()
        self.speed_mbps = 0.0
        self._path = None

    def start(self, size_mb, mode="seq_write"):
        if self.running:
            return
        self._stop.clear()
        self.running = True
        threading.Thread(target=self._run, args=(size_mb, mode), daemon=True).start()

    def _run(self, size_mb, mode):
        bs = 1024 * 1024
        total = size_mb * 1024 * 1024
        self._path = os.path.join(tempfile.gettempdir(), "stress_disk.tmp")
        try:
            if "write" in mode:
                self._write(total, bs, "random" in mode)
            else:
                self.log(f"Disk: preparing {size_mb} MB file...")
                d = os.urandom(bs)
                with open(self._path, "wb") as f:
                    w = 0
                    while w < total and not self._stop.is_set():
                        f.write(d)
                        w += bs
                if not self._stop.is_set():
                    self._read(total, bs, "random" in mode)
        except Exception as e:
            self.log(f"Disk error: {e}")
        finally:
            if self._path and os.path.exists(self._path):
                try:
                    os.remove(self._path)
                except Exception:
                    pass

    def _write(self, total, bs, rand):
        import random as rng
        self.log(f"Disk: {'random' if rand else 'sequential'} write...")
        data = os.urandom(bs)
        while not self._stop.is_set():
            fd = os.open(self._path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
            try:
                fcntl.fcntl(fd, fcntl.F_NOCACHE, 1)
            except Exception:
                pass
            w, t0 = 0, time.perf_counter()
            try:
                while w < total and not self._stop.is_set():
                    if rand:
                        os.lseek(fd, rng.randint(0, max(0, total - bs)), os.SEEK_SET)
                    os.write(fd, data)
                    w += bs
                os.fsync(fd)
            finally:
                os.close(fd)
            dt = time.perf_counter() - t0
            if dt > 0:
                self.speed_mbps = (w / (1024 * 1024)) / dt

    def _read(self, total, bs, rand):
        import random as rng
        self.log(f"Disk: {'random' if rand else 'sequential'} read...")
        while not self._stop.is_set():
            fd = os.open(self._path, os.O_RDONLY)
            try:
                fcntl.fcntl(fd, fcntl.F_NOCACHE, 1)
            except Exception:
                pass
            r, t0 = 0, time.perf_counter()
            try:
                while r < total and not self._stop.is_set():
                    if rand:
                        os.lseek(fd, rng.randint(0, max(0, total - bs)), os.SEEK_SET)
                    d = os.read(fd, bs)
                    if not d:
                        os.lseek(fd, 0, os.SEEK_SET)
                        continue
                    r += len(d)
            finally:
                os.close(fd)
            dt = time.perf_counter() - t0
            if dt > 0:
                self.speed_mbps = (r / (1024 * 1024)) / dt

    def stop(self):
        if not self.running:
            return
        self._stop.set()
        self.running = False
        self.speed_mbps = 0.0
        self.log("Disk: stopped")


# ═══════════════════════════════════════════════════════════
# Main Application
# ═══════════════════════════════════════════════════════════

class StressTestApp:
    def __init__(self, root):
        self.root = root
        self.sys = get_system_info()
        self.cpu_procs, self.cpu_stop_event, self.cpu_running = [], None, False
        self.gpu = GPUStressManager(log_cb=self._log)
        self.ram = RAMStressManager(log_cb=self._log)
        self.disk = DiskStressManager(log_cb=self._log)
        self._dur_timer = None
        self._ram_target = 0
        self._build()
        self._start_mon()

    def _build(self):
        self.root.title("MacBook Stress Test")
        self.root.configure(bg=A['window'])
        self.root.geometry("820x1000")
        self.root.minsize(780, 900)

        m = tk.Frame(self.root, bg=A['window'])
        m.pack(fill='both', expand=True, padx=22, pady=18)

        self._header(m)
        self._cpu_card(m)
        self._gpu_card(m)
        self._ram_card(m)
        self._disk_card(m)
        self._monitor_card(m)
        # bottom action bar is pinned to the window; the log fills the gap
        self._bottom(m)
        self._log_card(m)

    # ── Header ─────────────────────────────────────────────

    def _header(self, p):
        f = tk.Frame(p, bg=A['window'])
        f.pack(fill='x', pady=(0, 14))

        title = tk.Frame(f, bg=A['window'])
        title.pack(fill='x')
        tk.Label(title, text="Stress Test", bg=A['window'], fg=A['label'],
                 font=(FONT, 30, 'bold')).pack(anchor='w')
        tk.Label(title, text="System-Belastungstest · CPU · GPU · Memory · Disk",
                 bg=A['window'], fg=A['label_ter'],
                 font=(FONT, 12)).pack(anchor='w', pady=(2, 0))

        info = self.sys
        cores = f"{info['cores_logical']} Cores"
        if info.get("p_cores") and info.get("e_cores"):
            cores += f" · {info['p_cores']}P + {info['e_cores']}E"
        ram = f"{info['ram_total'] / (1024**3):.0f} GB RAM"

        chips = tk.Frame(f, bg=A['window'])
        chips.pack(fill='x', pady=(13, 0))
        for text, dot in [
            (_clean_cpu(info['cpu']), A['blue']),
            (cores, A['green']),
            (ram, A['purple']),
            (f"macOS {info['os_version']}", A['teal']),
        ]:
            InfoChip(chips, text, dot=dot).pack(side='left', padx=(0, 8))

        tk.Frame(f, bg=A['outline'], height=1).pack(fill='x', pady=(14, 0))

    # ── CPU ────────────────────────────────────────────────

    def _cpu_card(self, p):
        card = RoundedCard(p)
        card.pack(fill='x', pady=5)
        b = card.inner

        # Title row
        top = tk.Frame(b, bg=A['card'])
        top.pack(fill='x')
        self._cpu_dot = IconTile(top, 'cpu', A['blue'])
        self._cpu_dot.pack(side='left', padx=(0, 10))
        tk.Label(top, text="CPU", bg=A['card'], fg=A['label'],
                 font=(FONT, 15, 'bold')).pack(side='left')
        self._cpu_status = tk.Label(top, text="Idle", bg=A['card'], fg=A['label_ter'],
                                     font=(FONT, 12))
        self._cpu_status.pack(side='right')

        # Controls
        row1 = tk.Frame(b, bg=A['card'])
        row1.pack(fill='x', pady=(10, 0))

        tk.Label(row1, text="Cores", bg=A['card'], fg=A['label_sec'],
                 font=(FONT, 12)).pack(side='left')
        self.cpu_cores = tk.IntVar(value=self.sys["cores_logical"])
        AppleSlider(row1, 1, self.sys["cores_logical"], self.cpu_cores,
                    color=A['blue']).pack(side='left', padx=(10, 8))
        tk.Label(row1, textvariable=self.cpu_cores, bg=A['card'], fg=A['label'],
                 font=(FONT_MONO, 12, 'bold'), width=2).pack(side='left', padx=(0, 16))

        tk.Label(row1, text="Workload", bg=A['card'], fg=A['label_sec'],
                 font=(FONT, 12)).pack(side='left', padx=(0, 8))
        self.cpu_mode = tk.StringVar(value="mixed")
        SegmentedControl(row1, [("Float", "float"), ("Integer", "integer"), ("Mixed", "mixed")],
                         self.cpu_mode).pack(side='left')

        row2 = tk.Frame(b, bg=A['card'])
        row2.pack(fill='x', pady=(10, 0))

        tk.Label(row2, text="Duration", bg=A['card'], fg=A['label_sec'],
                 font=(FONT, 12)).pack(side='left', padx=(0, 8))
        self.cpu_dur = tk.StringVar(value="Unlimited")
        SegmentedControl(row2,
                         [("30s", "30 sec"), ("1m", "1 min"), ("5m", "5 min"),
                          ("30m", "30 min"), ("\u221e", "Unlimited")],
                         self.cpu_dur).pack(side='left')

        self._cpu_stop_btn = AppleButton(row2, "Stop", self._stop_cpu,
                                          color=A['red'], style='tinted', font_size=11)
        self._cpu_stop_btn.pack(side='right', padx=(6, 0))
        self._cpu_stop_btn.set_enabled(False)

        self._cpu_start_btn = AppleButton(row2, "Start", self._start_cpu,
                                           color=A['green'], font_size=11)
        self._cpu_start_btn.pack(side='right')

    # ── GPU ────────────────────────────────────────────────

    def _gpu_card(self, p):
        card = RoundedCard(p)
        card.pack(fill='x', pady=5)
        b = card.inner

        top = tk.Frame(b, bg=A['card'])
        top.pack(fill='x')
        self._gpu_dot = IconTile(top, 'gpu', A['teal'])
        self._gpu_dot.pack(side='left', padx=(0, 10))
        tk.Label(top, text="GPU  Metal", bg=A['card'], fg=A['label'],
                 font=(FONT, 15, 'bold')).pack(side='left')
        self._gpu_status = tk.Label(top, text="Idle", bg=A['card'], fg=A['label_ter'],
                                     font=(FONT, 12))
        self._gpu_status.pack(side='right')

        row = tk.Frame(b, bg=A['card'])
        row.pack(fill='x', pady=(10, 0))

        tk.Label(row, text="Buffer", bg=A['card'], fg=A['label_sec'],
                 font=(FONT, 12)).pack(side='left', padx=(0, 8))
        self.gpu_buf = tk.StringVar(value="256")
        SegmentedControl(row, [("64", "64"), ("128", "128"), ("256", "256"),
                                ("512", "512"), ("1024", "1024")],
                         self.gpu_buf).pack(side='left')
        tk.Label(row, text="MB", bg=A['card'], fg=A['label_ter'],
                 font=(FONT, 12)).pack(side='left', padx=(6, 0))

        self._gpu_stop = AppleButton(row, "Stop", self._stop_gpu,
                                      color=A['red'], style='tinted', font_size=11)
        self._gpu_stop.pack(side='right', padx=(6, 0))
        self._gpu_stop.set_enabled(False)
        self._gpu_start = AppleButton(row, "Start", self._start_gpu,
                                       color=A['green'], font_size=11)
        self._gpu_start.pack(side='right')

    # ── RAM ────────────────────────────────────────────────

    def _ram_card(self, p):
        card = RoundedCard(p)
        card.pack(fill='x', pady=5)
        b = card.inner

        top = tk.Frame(b, bg=A['card'])
        top.pack(fill='x')
        self._ram_dot = IconTile(top, 'memory', A['purple'])
        self._ram_dot.pack(side='left', padx=(0, 10))
        tk.Label(top, text="Memory", bg=A['card'], fg=A['label'],
                 font=(FONT, 15, 'bold')).pack(side='left')
        self._ram_status = tk.Label(top, text="Idle", bg=A['card'], fg=A['label_ter'],
                                     font=(FONT, 12))
        self._ram_status.pack(side='right')

        row = tk.Frame(b, bg=A['card'])
        row.pack(fill='x', pady=(10, 0))

        avail = self.sys["ram_available"] / (1024 ** 3)
        total = self.sys["ram_total"] / (1024 ** 3)

        tk.Label(row, text="Allocate", bg=A['card'], fg=A['label_sec'],
                 font=(FONT, 12)).pack(side='left', padx=(0, 8))
        self.ram_amt = tk.StringVar(value=str(max(1, int(avail * 0.5))))
        vals = [str(i) for i in range(1, int(total * 0.9) + 1)]
        SegmentedControl(row, [(f"{v}", v) for v in ["1", "2", "4", "8"]
                                if int(v) <= int(total * 0.9)],
                         self.ram_amt).pack(side='left')
        tk.Label(row, text=f"GB   ({avail:.1f} / {total:.0f} GB available)",
                 bg=A['card'], fg=A['label_ter'], font=(FONT, 11)).pack(side='left', padx=(8, 0))

        self._ram_stop = AppleButton(row, "Stop", self._stop_ram,
                                      color=A['red'], style='tinted', font_size=11)
        self._ram_stop.pack(side='right', padx=(6, 0))
        self._ram_stop.set_enabled(False)
        self._ram_start = AppleButton(row, "Start", self._start_ram,
                                       color=A['green'], font_size=11)
        self._ram_start.pack(side='right')

        # Progress
        bar_row = tk.Frame(b, bg=A['card'])
        bar_row.pack(fill='x', pady=(10, 0))
        self._ram_bar = AppleBar(bar_row, color=A['purple'])
        self._ram_bar.pack(side='left', fill='x', expand=True, padx=(0, 10))
        self._ram_lbl = tk.Label(bar_row, text="", bg=A['card'], fg=A['label_ter'],
                                  font=(FONT_MONO, 10), width=16, anchor='e')
        self._ram_lbl.pack(side='right')

    # ── Disk ───────────────────────────────────────────────

    def _disk_card(self, p):
        card = RoundedCard(p)
        card.pack(fill='x', pady=5)
        b = card.inner

        top = tk.Frame(b, bg=A['card'])
        top.pack(fill='x')
        self._disk_dot = IconTile(top, 'disk', A['orange'])
        self._disk_dot.pack(side='left', padx=(0, 10))
        tk.Label(top, text="Disk I/O", bg=A['card'], fg=A['label'],
                 font=(FONT, 15, 'bold')).pack(side='left')
        self._disk_status = tk.Label(top, text="Idle", bg=A['card'], fg=A['label_ter'],
                                      font=(FONT, 12))
        self._disk_status.pack(side='right')

        row = tk.Frame(b, bg=A['card'])
        row.pack(fill='x', pady=(10, 0))

        tk.Label(row, text="Size", bg=A['card'], fg=A['label_sec'],
                 font=(FONT, 12)).pack(side='left', padx=(0, 8))
        self.disk_sz = tk.StringVar(value="1024")
        SegmentedControl(row, [("256", "256"), ("512", "512"), ("1 GB", "1024"), ("4 GB", "4096")],
                         self.disk_sz).pack(side='left')

        tk.Frame(row, bg=A['card'], width=16).pack(side='left')

        tk.Label(row, text="Mode", bg=A['card'], fg=A['label_sec'],
                 font=(FONT, 12)).pack(side='left', padx=(0, 8))
        self.disk_mode = tk.StringVar(value="seq_write")
        SegmentedControl(row, [("Seq W", "seq_write"), ("Seq R", "seq_read"),
                                ("Rnd W", "random_write"), ("Rnd R", "random_read")],
                         self.disk_mode).pack(side='left')

        self._disk_speed = tk.Label(row, text="", bg=A['card'], fg=A['orange'],
                                     font=(FONT_MONO, 13, 'bold'))
        self._disk_speed.pack(side='left', padx=(12, 0))

        self._disk_stop = AppleButton(row, "Stop", self._stop_disk,
                                       color=A['red'], style='tinted', font_size=11)
        self._disk_stop.pack(side='right', padx=(6, 0))
        self._disk_stop.set_enabled(False)
        self._disk_start = AppleButton(row, "Start", self._start_disk,
                                        color=A['green'], font_size=11)
        self._disk_start.pack(side='right')

    # ── Monitor ────────────────────────────────────────────

    def _monitor_card(self, p):
        card = RoundedCard(p)
        card.pack(fill='x', pady=5)
        b = card.inner

        hdr = tk.Frame(b, bg=A['card'])
        hdr.pack(fill='x')
        IconTile(hdr, 'monitor', A['blue'], size=24).pack(side='left', padx=(0, 10))
        tk.Label(hdr, text="System Monitor", bg=A['card'], fg=A['label'],
                 font=(FONT, 15, 'bold')).pack(side='left')

        bars = tk.Frame(b, bg=A['card'])
        bars.pack(fill='x', pady=(8, 0))

        self._mon = {}
        for name, color in [("CPU", A['blue']), ("Memory", A['purple']), ("Swap", A['orange'])]:
            row = tk.Frame(bars, bg=A['card'])
            row.pack(fill='x', pady=3)
            tk.Label(row, text=name, bg=A['card'], fg=A['label_sec'],
                     font=(FONT, 11), width=7, anchor='w').pack(side='left')
            bar = AppleBar(row, height=6, color=color)
            bar.pack(side='left', fill='x', expand=True, padx=(0, 10))
            lbl = tk.Label(row, text="—", bg=A['card'], fg=A['label'],
                           font=(FONT_MONO, 11), width=20, anchor='e')
            lbl.pack(side='right')
            self._mon[name] = (bar, lbl)

        # Per-core
        tk.Label(b, text="Per-Core", bg=A['card'], fg=A['label_sec'],
                 font=(FONT, 11)).pack(anchor='w', pady=(10, 4))

        cf = tk.Frame(b, bg=A['card'])
        cf.pack(fill='x')
        n = self.sys["cores_logical"]
        cols = min(5, n)
        self._cbars, self._clbls = [], []
        for i in range(n):
            r, c = divmod(i, cols)
            cell = tk.Frame(cf, bg=A['card'])
            cell.grid(row=r, column=c, padx=3, pady=2, sticky='ew')
            cf.columnconfigure(c, weight=1)

            tk.Label(cell, text=str(i), bg=A['card'], fg=A['label_ter'],
                     font=(FONT_MONO, 9), width=2).pack(side='left')
            bar = AppleBar(cell, height=5, color=A['blue'])
            bar.pack(side='left', fill='x', expand=True, padx=2)
            lbl = tk.Label(cell, text="—", bg=A['card'], fg=A['label_ter'],
                           font=(FONT_MONO, 9), width=4, anchor='e')
            lbl.pack(side='right')
            self._cbars.append(bar)
            self._clbls.append(lbl)

    # ── Log ────────────────────────────────────────────────

    def _log_card(self, p):
        card = RoundedCard(p, pad_y=4)
        card.pack(fill='both', expand=True, pady=5)
        b = card.inner

        tk.Label(b, text="Activity", bg=A['card'], fg=A['label_sec'],
                 font=(FONT, 11, 'bold')).pack(anchor='w', pady=(2, 4))

        f = tk.Frame(b, bg=A['card'])
        f.pack(fill='both', expand=True)

        self._log_txt = tk.Text(f, bg='#16161a', fg=A['label_sec'],
                                 font=(FONT_MONO, 10), height=4, bd=0,
                                 highlightthickness=0, insertbackground=A['label_sec'],
                                 selectbackground=A['blue'], selectforeground='#fff',
                                 state='disabled', padx=12, pady=8, wrap='word',
                                 spacing1=1, spacing3=1)
        self._log_txt.pack(fill='both', expand=True)

    # ── Bottom ─────────────────────────────────────────────

    def _bottom(self, p):
        f = tk.Frame(p, bg=A['window'])
        f.pack(side='bottom', fill='x', pady=(14, 0))
        AppleButton(f, "Run All Tests", self._start_all,
                    color=A['blue'], font_size=13, pad_x=24, pad_y=9).pack(side='left')
        AppleButton(f, "Stop All", self._stop_all,
                    color=A['red'], style='tinted', font_size=13, pad_x=24, pad_y=9
                    ).pack(side='left', padx=(10, 0))

    # ── Actions ────────────────────────────────────────────

    def _start_cpu(self):
        if self.cpu_running:
            return
        cores = self.cpu_cores.get()
        mode = self.cpu_mode.get()
        self.cpu_stop_event = mp.Event()
        self.cpu_procs = []
        for _ in range(cores):
            pr = mp.Process(target=cpu_stress_worker, args=(self.cpu_stop_event, mode), daemon=True)
            pr.start()
            self.cpu_procs.append(pr)
        self.cpu_running = True
        self._cpu_start_btn.set_enabled(False)
        self._cpu_stop_btn.set_enabled(True)
        self._cpu_dot.activate()
        self._cpu_status.config(text=f"{cores} cores \u00b7 {mode}", fg=A['blue'])
        self._log(f"CPU: {cores} cores, {mode}")
        d = self.cpu_dur.get()
        if d != "Unlimited":
            s = {"30 sec": 30, "1 min": 60, "5 min": 300, "30 min": 1800}.get(d)
            if s:
                self._dur_timer = self.root.after(s * 1000, self._stop_all)
                self._log(f"Auto-stop in {d}")

    def _stop_cpu(self):
        if not self.cpu_running:
            return
        if self._dur_timer:
            self.root.after_cancel(self._dur_timer)
            self._dur_timer = None
        self.cpu_stop_event.set()

        def join():
            for pr in self.cpu_procs:
                pr.join(timeout=3)
                if pr.is_alive():
                    pr.terminate()
            self.cpu_procs.clear()
            self.root.after(0, lambda: self._log("CPU: stopped"))

        threading.Thread(target=join, daemon=True).start()
        self.cpu_running = False
        self._cpu_start_btn.set_enabled(True)
        self._cpu_stop_btn.set_enabled(False)
        self._cpu_dot.deactivate()
        self._cpu_status.config(text="Idle", fg=A['label_ter'])

    def _start_gpu(self):
        if self.gpu.running:
            return
        mb = int(self.gpu_buf.get())
        self._gpu_start.set_enabled(False)
        self._gpu_dot.activate(A['teal'])
        self._gpu_status.config(text="Starting...", fg=A['teal'])
        self._log(f"GPU: starting ({mb} MB)...")

        def go():
            self.gpu.start(mb)
            self.root.after(0, lambda: self._gpu_stop.set_enabled(True))
            self.root.after(0, lambda: self._gpu_status.config(text=f"{mb} MB buffer", fg=A['teal']))

        threading.Thread(target=go, daemon=True).start()

    def _stop_gpu(self):
        if not self.gpu.running:
            return
        self.gpu.stop()
        self._gpu_start.set_enabled(True)
        self._gpu_stop.set_enabled(False)
        self._gpu_dot.deactivate()
        self._gpu_status.config(text="Idle", fg=A['label_ter'])
        self._log("GPU: stopped")

    def _start_ram(self):
        if self.ram.running:
            return
        try:
            gb = int(self.ram_amt.get())
        except ValueError:
            return
        self._ram_target = gb * 1024
        self.ram.start(self._ram_target)
        self._ram_start.set_enabled(False)
        self._ram_stop.set_enabled(True)
        self._ram_dot.activate(A['purple'])
        self._ram_status.config(text=f"Allocating {gb} GB...", fg=A['purple'])
        self._log(f"RAM: {gb} GB")

    def _stop_ram(self):
        if not self.ram.running:
            return
        self.ram.stop()
        self._ram_start.set_enabled(True)
        self._ram_stop.set_enabled(False)
        self._ram_dot.deactivate()
        self._ram_status.config(text="Idle", fg=A['label_ter'])
        self._ram_bar.set(0)
        self._ram_lbl.config(text="")

    def _start_disk(self):
        if self.disk.running:
            return
        sz = int(self.disk_sz.get())
        mode = self.disk_mode.get()
        self.disk.start(sz, mode)
        self._disk_start.set_enabled(False)
        self._disk_stop.set_enabled(True)
        self._disk_dot.activate(A['orange'])
        self._disk_status.config(text=f"{mode} \u00b7 {sz} MB", fg=A['orange'])
        self._log(f"Disk: {mode}, {sz} MB")

    def _stop_disk(self):
        if not self.disk.running:
            return
        self.disk.stop()
        self._disk_start.set_enabled(True)
        self._disk_stop.set_enabled(False)
        self._disk_dot.deactivate()
        self._disk_status.config(text="Idle", fg=A['label_ter'])
        self._disk_speed.config(text="")

    def _start_all(self):
        self._log("=== Starting all ===")
        if not self.cpu_running:
            self._start_cpu()
        if not self.gpu.running:
            self._start_gpu()
        if not self.ram.running:
            self._start_ram()
        if not self.disk.running:
            self._start_disk()

    def _stop_all(self):
        self._log("=== Stopping all ===")
        self._stop_cpu()
        self._stop_gpu()
        self._stop_ram()
        self._stop_disk()

    # ── Monitoring ─────────────────────────────────────────

    def _start_mon(self):
        if psutil:
            psutil.cpu_percent(percpu=True)
        self._update()

    def _update(self):
        try:
            if psutil:
                cp = psutil.cpu_percent()
                b, l = self._mon["CPU"]
                b.set(cp)
                l.config(text=f"{cp:.0f} %")

                pc = psutil.cpu_percent(percpu=True)
                for i, v in enumerate(pc):
                    if i < len(self._cbars):
                        self._cbars[i].set(v)
                        self._clbls[i].config(text=f"{v:.0f}%")

                mem = psutil.virtual_memory()
                b, l = self._mon["Memory"]
                b.set(mem.percent)
                l.config(text=f"{mem.percent:.0f} %   "
                              f"{mem.used/(1024**3):.1f} / {mem.total/(1024**3):.0f} GB")

                sw = psutil.swap_memory()
                b, l = self._mon["Swap"]
                b.set(sw.percent)
                l.config(text=f"{sw.percent:.0f} %   {sw.used/(1024**3):.1f} GB")

            if self.ram.running:
                al = self.ram.allocated_mb
                t = self._ram_target or 1
                self._ram_bar.set(min(100, al / t * 100))
                self._ram_lbl.config(text=f"{al} / {t} MB")
                if al >= t:
                    self._ram_status.config(text=f"{al} MB active", fg=A['purple'])

            if self.disk.running and self.disk.speed_mbps > 0:
                self._disk_speed.config(text=f"{self.disk.speed_mbps:.0f} MB/s")

            if self.gpu.running and self.gpu.iter_rate > 0:
                self._gpu_status.config(
                    text=f"{self.gpu.iter_rate:.1f} iter/s \u00b7 {self.gpu_buf.get()} MB",
                    fg=A['teal'])

        except Exception:
            pass
        self.root.after(1000, self._update)

    # ── Log ────────────────────────────────────────────────

    def _log(self, msg):
        ts = datetime.now().strftime("%H:%M:%S")
        line = f"{ts}   {msg}\n"

        def add():
            self._log_txt.config(state='normal')
            self._log_txt.insert('end', line)
            self._log_txt.see('end')
            self._log_txt.config(state='disabled')

        if threading.current_thread() is threading.main_thread():
            add()
        else:
            self.root.after(0, add)

    def on_close(self):
        self._stop_all()
        time.sleep(0.3)
        self.root.destroy()


# ═══════════════════════════════════════════════════════════
# Entry Point
# ═══════════════════════════════════════════════════════════

def main():
    if sys.platform == "darwin":
        try:
            mp.set_start_method("spawn")
        except RuntimeError:
            pass

    root = tk.Tk()
    app = StressTestApp(root)
    root.protocol("WM_DELETE_WINDOW", app.on_close)
    try:
        root.mainloop()
    except KeyboardInterrupt:
        app.on_close()


if __name__ == "__main__":
    main()
