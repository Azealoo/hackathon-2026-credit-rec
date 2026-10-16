"""Minimal TrueType (glyf + gvar) outline reader. Python standard library only."""
import struct

class Font:
    def __init__(self, path):
        self.d = d = open(path, 'rb').read()
        n = struct.unpack('>H', d[4:6])[0]
        self.t = {}
        for i in range(n):
            tag, _, off, ln = struct.unpack('>4sIII', d[12 + 16 * i:28 + 16 * i])
            self.t[tag.decode()] = (off, ln)
        self.upm = struct.unpack('>H', d[self.t['head'][0] + 18:self.t['head'][0] + 20])[0]
        self.loca_fmt = struct.unpack('>h', d[self.t['head'][0] + 50:self.t['head'][0] + 52])[0]
        self.nglyphs = struct.unpack('>H', d[self.t['maxp'][0] + 4:self.t['maxp'][0] + 6])[0]
        self._cmap()
        self._hmtx()
        self._axes()
        self._gvar_header()

    def u16(self, o): return struct.unpack('>H', self.d[o:o + 2])[0]
    def i16(self, o): return struct.unpack('>h', self.d[o:o + 2])[0]
    def u32(self, o): return struct.unpack('>I', self.d[o:o + 4])[0]

    def _cmap(self):
        base = self.t['cmap'][0]
        n = self.u16(base + 2)
        self.cmap = {}
        for i in range(n):
            pid, eid, off = struct.unpack('>HHI', self.d[base + 4 + 8 * i:base + 12 + 8 * i])
            o = base + off
            fmt = self.u16(o)
            if fmt == 4 and pid in (0, 3):
                segx2 = self.u16(o + 6)
                ends = o + 14
                starts = ends + segx2 + 2
                deltas = starts + segx2
                ranges = deltas + segx2
                for s in range(segx2 // 2):
                    e, st = self.u16(ends + 2 * s), self.u16(starts + 2 * s)
                    dl, ro = self.i16(deltas + 2 * s), self.u16(ranges + 2 * s)
                    for c in range(st, e + 1):
                        if c == 0xFFFF:
                            continue
                        if ro == 0:
                            g = (c + dl) & 0xFFFF
                        else:
                            g = self.u16(ranges + 2 * s + ro + 2 * (c - st))
                            if g:
                                g = (g + dl) & 0xFFFF
                        self.cmap.setdefault(c, g)

    def _hmtx(self):
        nh = self.u16(self.t['hhea'][0] + 34)
        base = self.t['hmtx'][0]
        self.adv = [self.u16(base + 4 * min(i, nh - 1)) for i in range(self.nglyphs)]

    def _axes(self):
        off = self.t['fvar'][0]
        axoff, axcount, axsize = self.u16(off + 4), self.u16(off + 8), self.u16(off + 10)
        self.axes = []
        for a in range(axcount):
            o = off + axoff + a * axsize
            tag = self.d[o:o + 4].decode()
            mn, df, mx = [v / 65536 for v in struct.unpack('>iii', self.d[o + 4:o + 16])]
            self.axes.append((tag, mn, df, mx))
        self.avar = None
        if 'avar' in self.t:
            o = self.t['avar'][0] + 8
            self.avar = []
            for _ in range(len(self.axes)):
                cnt = self.u16(o); o += 2
                m = []
                for _ in range(cnt):
                    m.append((self.i16(o) / 16384, self.i16(o + 2) / 16384)); o += 4
                self.avar.append(m)

    def norm(self, coords):
        out = []
        for i, (tag, mn, df, mx) in enumerate(self.axes):
            v = coords.get(tag, df)
            v = max(mn, min(mx, v))
            n = 0.0 if v == df else ((v - df) / (df - mn) if v < df else (v - df) / (mx - df))
            if self.avar and self.avar[i]:
                m = self.avar[i]
                for k in range(1, len(m)):
                    if n <= m[k][0]:
                        a, b = m[k - 1], m[k]
                        n = a[1] + (b[1] - a[1]) * (n - a[0]) / (b[0] - a[0]) if b[0] != a[0] else b[1]
                        break
            out.append(n)
        return out

    def _gvar_header(self):
        g = self.t['gvar'][0]
        self.gv = g
        self.axc = self.u16(g + 4)
        shared_cnt = self.u16(g + 6)
        shared_off = self.u32(g + 8)
        flags = self.u16(g + 14)
        data_off = self.u32(g + 16)
        self.gv_data = g + data_off
        self.gv_long = flags & 1
        self.gv_offs = g + 20
        self.shared = []
        o = g + shared_off
        for _ in range(shared_cnt):
            self.shared.append([self.i16(o + 2 * k) / 16384 for k in range(self.axc)])
            o += 2 * self.axc

    def _gvar_off(self, gid):
        if self.gv_long:
            return self.u32(self.gv_offs + 4 * gid), self.u32(self.gv_offs + 4 * gid + 4)
        return self.u16(self.gv_offs + 2 * gid) * 2, self.u16(self.gv_offs + 2 * gid + 2) * 2

    def _glyf(self, gid):
        lo = self.t['loca'][0]
        if self.loca_fmt == 0:
            a, b = self.u16(lo + 2 * gid) * 2, self.u16(lo + 2 * gid + 2) * 2
        else:
            a, b = self.u32(lo + 4 * gid), self.u32(lo + 4 * gid + 4)
        return self.t['glyf'][0] + a, b - a

    def _simple(self, o):
        nc = self.i16(o)
        ends = [self.u16(o + 10 + 2 * i) for i in range(nc)]
        npts = ends[-1] + 1 if ends else 0
        p = o + 10 + 2 * nc
        il = self.u16(p); p += 2 + il
        flags = []
        while len(flags) < npts:
            f = self.d[p]; p += 1
            flags.append(f)
            if f & 8:
                r = self.d[p]; p += 1
                flags.extend([f] * r)
        xs, ys = [], []
        v = 0
        for f in flags:
            if f & 2:
                dv = self.d[p]; p += 1
                v += dv if f & 16 else -dv
            elif not f & 16:
                v += self.i16(p); p += 2
            xs.append(v)
        v = 0
        for f in flags:
            if f & 4:
                dv = self.d[p]; p += 1
                v += dv if f & 32 else -dv
            elif not f & 32:
                v += self.i16(p); p += 2
            ys.append(v)
        on = [bool(f & 1) for f in flags]
        return ends, [list(a) for a in zip(xs, ys)], on

    @staticmethod
    def _packed_points(d, p):
        cnt = d[p]; p += 1
        if cnt == 0:
            return None, p
        if cnt & 0x80:
            cnt = ((cnt & 0x7F) << 8) | d[p]; p += 1
        pts, v = [], 0
        while len(pts) < cnt:
            hdr = d[p]; p += 1
            run = (hdr & 0x7F) + 1
            for _ in range(run):
                if hdr & 0x80:
                    v += struct.unpack('>H', d[p:p + 2])[0]; p += 2
                else:
                    v += d[p]; p += 1
                pts.append(v)
        return pts, p

    @staticmethod
    def _packed_deltas(d, p, n):
        out = []
        while len(out) < n:
            hdr = d[p]; p += 1
            run = (hdr & 0x3F) + 1
            if hdr & 0x80:
                out.extend([0] * run)
            elif hdr & 0x40:
                out.extend(struct.unpack('>%dh' % run, d[p:p + 2 * run])); p += 2 * run
            else:
                out.extend(struct.unpack('>%db' % run, d[p:p + run])); p += run
        return out, p

    def _deltas(self, gid, npts_total, ends, coords, pts_orig):
        a, b = self._gvar_off(gid)
        if b == a:
            return [[0.0, 0.0] for _ in range(npts_total)]
        d = self.d
        base = self.gv_data + a
        cnt_word = self.u16(base)
        cnt = cnt_word & 0x0FFF
        data = base + self.u16(base + 2)
        hp = base + 4
        shared_pts = None
        if cnt_word & 0x8000:
            shared_pts, data = self._packed_points(d, data)
        total = [[0.0, 0.0] for _ in range(npts_total)]
        for _ in range(cnt):
            size = self.u16(hp); idx = self.u16(hp + 2); hp += 4
            if idx & 0x8000:
                peak = [self.i16(hp + 2 * k) / 16384 for k in range(self.axc)]; hp += 2 * self.axc
            else:
                peak = self.shared[idx & 0x0FFF]
            if idx & 0x4000:
                st = [self.i16(hp + 2 * k) / 16384 for k in range(self.axc)]; hp += 2 * self.axc
                en = [self.i16(hp + 2 * k) / 16384 for k in range(self.axc)]; hp += 2 * self.axc
            else:
                st = en = None
            scalar = 1.0
            for k in range(self.axc):
                pk, c = peak[k], coords[k]
                if pk == 0:
                    continue
                if c == 0:
                    scalar = 0; break
                if st is None:
                    s0, e0 = min(0, pk), max(0, pk)
                else:
                    s0, e0 = st[k], en[k]
                if c < s0 or c > e0:
                    scalar = 0; break
                if c < pk:
                    scalar *= (c - s0) / (pk - s0) if pk != s0 else 1
                elif c > pk:
                    scalar *= (e0 - c) / (e0 - pk) if e0 != pk else 1
            p = data
            if idx & 0x2000:
                pts, p = self._packed_points(d, p)
            else:
                pts = shared_pts
            npt = npts_total if pts is None else len(pts)
            dx, p = self._packed_deltas(d, p, npt)
            dy, p = self._packed_deltas(d, p, npt)
            data += size
            if scalar == 0:
                continue
            if pts is None:
                for i in range(npts_total):
                    total[i][0] += dx[i] * scalar; total[i][1] += dy[i] * scalar
            else:
                got = {}
                for i, pi in enumerate(pts):
                    if pi < npts_total:
                        got[pi] = (dx[i], dy[i])
                full = self._iup(got, ends, pts_orig, npts_total)
                for i in range(npts_total):
                    total[i][0] += full[i][0] * scalar; total[i][1] += full[i][1] * scalar
        return total

    @staticmethod
    def _iup(got, ends, pts, ntotal):
        out = [[0.0, 0.0] for _ in range(ntotal)]
        for i, v in got.items():
            out[i] = [float(v[0]), float(v[1])]
        start = 0
        for e in ends:
            idxs = [i for i in range(start, e + 1) if i in got]
            if idxs:
                n = e - start + 1
                for i in range(start, e + 1):
                    if i in got:
                        continue
                    # previous and next touched (cyclic)
                    prv = max([j for j in idxs if j < i], default=idxs[-1])
                    nxt = min([j for j in idxs if j > i], default=idxs[0])
                    for ax in (0, 1):
                        a, b = pts[prv][ax], pts[nxt][ax]
                        da, db = got[prv][ax], got[nxt][ax]
                        x = pts[i][ax]
                        if a == b:
                            out[i][ax] = da if da == db else 0.0
                        else:
                            lo, hi, dlo, dhi = (a, b, da, db) if a < b else (b, a, db, da)
                            if x <= lo:
                                out[i][ax] = dlo
                            elif x >= hi:
                                out[i][ax] = dhi
                            else:
                                out[i][ax] = dlo + (dhi - dlo) * (x - lo) / (hi - lo)
            start = e + 1
        return out

    def glyph(self, gid, coords):
        """Return (contours, advance) where contours are lists of (x, y, on)."""
        o, ln = self._glyf(gid)
        adv = self.adv[gid]
        if ln == 0:
            dl = self._deltas(gid, 4, [], coords, [[0, 0]] * 4)
            return [], adv + dl[1][0] - dl[0][0]
        nc = self.i16(o)
        if nc < 0:
            raise NotImplementedError('composite glyph')
        ends, pts, on = self._simple(o)
        n = len(pts)
        allpts = pts + [[0, 0], [adv, 0], [0, 0], [0, 0]]
        dl = self._deltas(gid, n + 4, ends, coords, allpts)
        moved = [(allpts[i][0] + dl[i][0], allpts[i][1] + dl[i][1]) for i in range(n + 4)]
        adv2 = moved[n + 1][0] - moved[n][0]
        contours, s = [], 0
        for e in ends:
            contours.append([(moved[i][0], moved[i][1], on[i]) for i in range(s, e + 1)])
            s = e + 1
        return contours, adv2

def contour_path(c, ox, oy, sc):
    """TrueType quadratic contour -> SVG path (y flipped)."""
    P = lambda x, y: (ox + x * sc, oy - y * sc)
    n = len(c)
    # find start on-curve
    start = next((i for i in range(n) if c[i][2]), None)
    pts = c[start:] + c[:start] if start is not None else c
    if start is None:
        x0 = (c[0][0] + c[1][0]) / 2; y0 = (c[0][1] + c[1][1]) / 2
        pts = [(x0, y0, True)] + c[1:] + c[:1]
    f = lambda v: f"{v:.2f}".rstrip('0').rstrip('.')
    x, y = P(pts[0][0], pts[0][1])
    d = [f"M{f(x)} {f(y)}"]
    i = 1
    seq = pts[1:] + [pts[0]]
    k = 0
    while k < len(seq):
        p = seq[k]
        if p[2]:
            x, y = P(p[0], p[1]); d.append(f"L{f(x)} {f(y)}"); k += 1
        else:
            nx = seq[k + 1] if k + 1 < len(seq) else pts[0]
            if nx[2]:
                end = nx; k += 2
            else:
                end = ((p[0] + nx[0]) / 2, (p[1] + nx[1]) / 2, True); k += 1
            cx, cy = P(p[0], p[1]); ex, ey = P(end[0], end[1])
            d.append(f"Q{f(cx)} {f(cy)} {f(ex)} {f(ey)}")
    d.append('Z')
    return ''.join(d)

def text_path(font, text, size, coords, tracking=0.0, x=0.0, baseline=0.0):
    nc = font.norm(coords)
    sc = size / font.upm
    ds, cx = [], x
    for ch in text:
        gid = font.cmap.get(ord(ch), 0)
        contours, adv = font.glyph(gid, nc)
        for c in contours:
            ds.append(contour_path(c, cx, baseline, sc))
        cx += adv * sc + tracking * size
    return ''.join(ds), cx - x - tracking * size
