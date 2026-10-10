"""
Null Signal - hacker deck hardware generator.

Builds the main deck, the decrypt aux module and a program cartridge as
procedural Blender geometry, then renders each one with an orthographic,
pixel-exact camera:

    Visuals/Deck/<name>.png         beauty render (lit, transparent background)
    Visuals/Deck/<name>_albedo.png  flat colour pass (for 2D normal-mapped lighting)
    Visuals/Deck/<name>_normal.png  normal pass, OpenGL / Godot convention (Y+ up)
    Visuals/Deck/<name>.json        screen / lamp / port positions in image pixels

Run from the project root (Blender 4.x or 5.x):

    blender -b -P Tools/Blender/build_deck.py
    blender -b -P Tools/Blender/build_deck.py -- --only aux_decrypt --samples 32
    blender -b -P Tools/Blender/build_deck.py -- --fast        (beauty only, low samples)
    blender -b -P Tools/Blender/build_deck.py -- --gpu         (try CUDA/OptiX/HIP)
    blender -b -P Tools/Blender/build_deck.py -- --scale 2     (2x renders, metadata stays 1x)

Everything is laid out in game pixels (x right, y down, origin = device's
top-left corner). 1 Blender unit = 100 px. The metadata JSON is written from
the same numbers as the geometry, so Godot never has to be hand-aligned.
"""

import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Vector

PX = 0.01  # Blender units per pixel

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "Visuals", "Deck")
FONT_PATH = os.path.join(PROJECT_ROOT, "Visuals", "Fonts", "KodeMono-Bold.ttf")


# ---------------------------------------------------------------------------
# args
# ---------------------------------------------------------------------------

def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"only": None, "samples": 64, "scale": 1.0, "fast": False, "gpu": False, "no_blend": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--only":
            opts["only"] = argv[i + 1].split(",")
            i += 1
        elif a == "--samples":
            opts["samples"] = int(argv[i + 1])
            i += 1
        elif a == "--scale":
            opts["scale"] = float(argv[i + 1])
            i += 1
        elif a == "--fast":
            opts["fast"] = True
        elif a == "--gpu":
            opts["gpu"] = True
        elif a == "--no-blend":
            opts["no_blend"] = True
        i += 1
    if opts["fast"]:
        opts["samples"] = min(opts["samples"], 16)
    return opts


# ---------------------------------------------------------------------------
# scene reset
# ---------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    return scene


# ---------------------------------------------------------------------------
# node helpers (written to survive 4.x -> 5.x socket renames)
# ---------------------------------------------------------------------------

def sock(node, *names):
    for n in names:
        if n in node.inputs:
            return node.inputs[n]
    raise KeyError(f"{node.bl_idname}: none of {names}")


def out_sock(node, *names):
    for n in names:
        if n in node.outputs:
            return node.outputs[n]
    return node.outputs[0]


def typed_sock(sockets, name, stype):
    for s in sockets:
        if s.name == name and s.type == stype:
            return s
    raise KeyError(f"{name}/{stype}")


class NT:
    """Tiny wrapper so material graphs read top-to-bottom."""

    def __init__(self, nt):
        self.nt = nt
        self.N = nt.nodes
        self.L = nt.links

    def link(self, a, b):
        self.L.new(a, b)

    def node(self, kind, **inputs):
        n = self.N.new(kind)
        for k, v in inputs.items():
            sock(n, k).default_value = v
        return n

    def math(self, op, a, b=None, clamp=False):
        n = self.N.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        self._feed(n.inputs[0], a)
        if b is not None:
            self._feed(n.inputs[1], b)
        return n.outputs[0]

    def map_range(self, src, a, b, c=0.0, d=1.0):
        n = self.N.new("ShaderNodeMapRange")
        n.clamp = True
        self._feed(sock(n, "Value"), src)
        sock(n, "From Min").default_value = a
        sock(n, "From Max").default_value = b
        sock(n, "To Min").default_value = c
        sock(n, "To Max").default_value = d
        return out_sock(n, "Result")

    def mix_rgb(self, fac, a, b):
        n = self.N.new("ShaderNodeMix")
        n.data_type = "RGBA"
        self._feed(typed_sock(n.inputs, "Factor", "VALUE"), fac)
        self._feed(typed_sock(n.inputs, "A", "RGBA"), a)
        self._feed(typed_sock(n.inputs, "B", "RGBA"), b)
        return typed_sock(n.outputs, "Result", "RGBA")

    def _feed(self, socket, value):
        if hasattr(value, "is_output") or hasattr(value, "links"):
            self.link(value, socket)
        else:
            if isinstance(value, (tuple, list)) and len(value) == 3 and socket.type == "RGBA":
                value = (value[0], value[1], value[2], 1.0)
            socket.default_value = value


# Value nodes that flip every material between beauty / albedo / normal output.
PASS_FLAGS = {"albedo": [], "normal": []}


def set_pass(mode):
    for v in PASS_FLAGS["albedo"]:
        v.outputs[0].default_value = 1.0 if mode == "albedo" else 0.0
    for v in PASS_FLAGS["normal"]:
        v.outputs[0].default_value = 1.0 if mode == "normal" else 0.0


def new_material(name):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True  # deprecated (always on) in Blender 5
    except AttributeError:
        pass
    m.node_tree.nodes.clear()
    return m, NT(m.node_tree)


def finish_material(g, bsdf, base_color, normal=None):
    """Wire BSDF + albedo/normal debug emitters through the pass switches."""
    if normal is None:
        normal = out_sock(g.N.new("ShaderNodeNewGeometry"), "Normal")

    em_alb = g.N.new("ShaderNodeEmission")
    g._feed(sock(em_alb, "Color"), base_color)

    enc = g.N.new("ShaderNodeVectorMath")
    enc.operation = "MULTIPLY_ADD"
    g.link(normal, enc.inputs[0])
    enc.inputs[1].default_value = (0.5, 0.5, 0.5)
    enc.inputs[2].default_value = (0.5, 0.5, 0.5)
    em_nrm = g.N.new("ShaderNodeEmission")
    g.link(enc.outputs[0], sock(em_nrm, "Color"))

    f_alb = g.N.new("ShaderNodeValue")
    f_alb.outputs[0].default_value = 0.0
    f_nrm = g.N.new("ShaderNodeValue")
    f_nrm.outputs[0].default_value = 0.0
    PASS_FLAGS["albedo"].append(f_alb)
    PASS_FLAGS["normal"].append(f_nrm)

    mix1 = g.N.new("ShaderNodeMixShader")
    g.link(f_alb.outputs[0], mix1.inputs[0])
    g.link(bsdf.outputs[0], mix1.inputs[1])
    g.link(em_alb.outputs[0], mix1.inputs[2])
    mix2 = g.N.new("ShaderNodeMixShader")
    g.link(f_nrm.outputs[0], mix2.inputs[0])
    g.link(mix1.outputs[0], mix2.inputs[1])
    g.link(em_nrm.outputs[0], mix2.inputs[2])

    out = g.N.new("ShaderNodeOutputMaterial")
    g.link(mix2.outputs[0], sock(out, "Surface"))


def principled(g):
    return g.N.new("ShaderNodeBsdfPrincipled")


# ---------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------

def mat_worn_paint(name, color, rough=0.55, wear=1.0, grime=0.6, scratch=0.6,
                   metal=(0.42, 0.40, 0.37), bump=0.06, color_fn=None):
    """Painted milspec metal: grime mottling, edge wear to bare metal, fine scratches."""
    m, g = new_material(name)
    tc = g.N.new("ShaderNodeTexCoord")
    obj = out_sock(tc, "Object")

    # broad grime mottling
    n_grime = g.node("ShaderNodeTexNoise", Scale=2.2, Detail=8.0, Roughness=0.6)
    g.link(obj, sock(n_grime, "Vector"))
    grime_f = g.map_range(out_sock(n_grime, "Fac"), 0.35, 0.75)

    # directional scratches (noise stretched along one axis)
    mp = g.N.new("ShaderNodeMapping")
    sock(mp, "Scale").default_value = (1.5, 55.0, 1.5)
    sock(mp, "Rotation").default_value = (0.0, 0.0, 0.42)
    g.link(obj, sock(mp, "Vector"))
    n_scr = g.node("ShaderNodeTexNoise", Scale=3.5, Detail=2.0)
    g.link(mp.outputs[0], sock(n_scr, "Vector"))
    scr = g.map_range(out_sock(n_scr, "Fac"), 0.64, 0.70)

    # edge mask from bevel-normal vs geometry-normal
    bev = g.node("ShaderNodeBevel", Radius=0.025)
    geo = g.N.new("ShaderNodeNewGeometry")
    dot = g.N.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    g.link(out_sock(bev, "Normal"), dot.inputs[0])
    g.link(out_sock(geo, "Normal"), dot.inputs[1])
    edge = g.map_range(out_sock(dot, "Value"), 0.995, 0.85)

    n_break = g.node("ShaderNodeTexNoise", Scale=18.0, Detail=6.0)
    g.link(obj, sock(n_break, "Vector"))
    chip = g.math("MULTIPLY", edge, out_sock(n_break, "Fac"))
    chip = g.map_range(chip, 0.10, 0.20)
    wear_f = g.math("MAXIMUM", chip, g.math("MULTIPLY", scr, scratch))
    wear_f = g.math("MULTIPLY", wear_f, wear, clamp=True)

    # vertical grime streaks
    mp_s = g.N.new("ShaderNodeMapping")
    sock(mp_s, "Scale").default_value = (9.0, 0.6, 9.0)
    g.link(obj, sock(mp_s, "Vector"))
    n_streak = g.node("ShaderNodeTexNoise", Scale=2.0, Detail=4.0)
    g.link(mp_s.outputs[0], sock(n_streak, "Vector"))
    streak = g.map_range(out_sock(n_streak, "Fac"), 0.5, 0.75)
    grime_f = g.math("MAXIMUM", grime_f, g.math("MULTIPLY", streak, 0.7))

    paint = color_fn(g, obj) if color_fn else color
    dirty = g.mix_rgb(grime_f, paint, g.mix_rgb(grime, paint, (0.006, 0.006, 0.005)))
    base = g.mix_rgb(wear_f, dirty, metal)

    # cavity darkening: grime collects in corners and recess edges
    ao = g.N.new("ShaderNodeAmbientOcclusion")
    ao.only_local = True
    sock(ao, "Distance").default_value = 0.08
    cav = g.map_range(out_sock(ao, "AO"), 0.25, 1.0, 0.25, 1.0)
    base = g.mix_rgb(g.math("SUBTRACT", 1.0, cav, clamp=True), base, g.mix_rgb(0.85, base, (0.0, 0.0, 0.0)))

    bsdf = principled(g)
    g.link(base, sock(bsdf, "Base Color"))
    g.link(wear_f, sock(bsdf, "Metallic"))
    rough_s = g.math("ADD", g.math("MULTIPLY", wear_f, -0.25), rough)
    rough_s = g.math("ADD", rough_s, g.math("MULTIPLY", grime_f, 0.15), clamp=True)
    g.link(rough_s, sock(bsdf, "Roughness"))

    n_fine = g.node("ShaderNodeTexNoise", Scale=140.0, Detail=2.0)
    g.link(obj, sock(n_fine, "Vector"))
    height = g.math("ADD", g.math("MULTIPLY", scr, -0.6), g.math("MULTIPLY", out_sock(n_fine, "Fac"), 0.4))
    bmp = g.node("ShaderNodeBump", Strength=bump, Distance=0.01)
    g.link(height, sock(bmp, "Height"))
    g.link(out_sock(bmp, "Normal"), sock(bsdf, "Normal"))

    finish_material(g, bsdf, base, out_sock(bmp, "Normal"))
    return m


def mat_glass(name, tint=(0.004, 0.007, 0.005)):
    m, g = new_material(name)
    tc = g.N.new("ShaderNodeTexCoord")
    n = g.node("ShaderNodeTexNoise", Scale=4.0, Detail=4.0)
    g.link(out_sock(tc, "Object"), sock(n, "Vector"))
    smudge = g.map_range(out_sock(n, "Fac"), 0.4, 0.7, 0.06, 0.28)
    bsdf = principled(g)
    sock(bsdf, "Base Color").default_value = (*tint, 1.0)
    g.link(smudge, sock(bsdf, "Roughness"))
    finish_material(g, bsdf, tint)
    return m


def mat_plain(name, color, rough=0.5, metallic=0.0, emission=None, strength=0.0):
    m, g = new_material(name)
    bsdf = principled(g)
    sock(bsdf, "Base Color").default_value = (*color, 1.0)
    sock(bsdf, "Roughness").default_value = rough
    sock(bsdf, "Metallic").default_value = metallic
    if emission is not None:
        sock(bsdf, "Emission Color", "Emission").default_value = (*emission, 1.0)
        sock(bsdf, "Emission Strength").default_value = strength
    finish_material(g, bsdf, color)
    return m


def mat_lens(name, color=(0.006, 0.020, 0.010)):
    """Indicator lens: dark tinted plastic with fine horizontal diffuser ribs."""
    m, g = new_material(name)
    tc = g.N.new("ShaderNodeTexCoord")
    wave = g.N.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Y"
    sock(wave, "Scale").default_value = 35.0
    g.link(out_sock(tc, "Object"), sock(wave, "Vector"))
    ribs = g.map_range(out_sock(wave, "Fac"), 0.2, 0.8)
    bsdf = principled(g)
    base = g.mix_rgb(g.math("MULTIPLY", ribs, 0.35), color, (0.03, 0.06, 0.04))
    g.link(base, sock(bsdf, "Base Color"))
    sock(bsdf, "Roughness").default_value = 0.25
    bmp = g.node("ShaderNodeBump", Strength=0.35, Distance=0.004)
    g.link(ribs, sock(bmp, "Height"))
    g.link(out_sock(bmp, "Normal"), sock(bsdf, "Normal"))
    finish_material(g, bsdf, base, out_sock(bmp, "Normal"))
    return m


def hazard_color(g, obj):
    mp = g.N.new("ShaderNodeMapping")
    sock(mp, "Rotation").default_value = (0.0, 0.0, math.radians(45))
    g.link(obj, sock(mp, "Vector"))
    sep = g.N.new("ShaderNodeSeparateXYZ")
    g.link(mp.outputs[0], sep.inputs[0])
    stripes = g.math("FRACT", g.math("MULTIPLY", sep.outputs[0], 7.0))
    stripes = g.map_range(stripes, 0.49, 0.51)
    return g.mix_rgb(stripes, (0.62, 0.40, 0.015), (0.012, 0.012, 0.010))


def build_materials():
    M = {}
    M["deck"] = mat_worn_paint("deck_gunmetal", (0.040, 0.043, 0.036), rough=0.6)
    M["plate"] = mat_worn_paint("deck_olive", (0.060, 0.066, 0.042), rough=0.55)
    M["trim"] = mat_worn_paint("trim_black", (0.018, 0.018, 0.019), rough=0.36, wear=0.7,
                               metal=(0.35, 0.34, 0.33))
    M["khaki"] = mat_worn_paint("module_khaki", (0.15, 0.12, 0.072), rough=0.6)
    M["cart"] = mat_worn_paint("cart_grey", (0.30, 0.30, 0.28), rough=0.5, wear=0.5, grime=0.3)
    M["hazard"] = mat_worn_paint("hazard", (0, 0, 0), rough=0.6, wear=1.2, color_fn=hazard_color)
    M["stencil"] = mat_worn_paint("stencil", (0.55, 0.53, 0.45), rough=0.75, wear=0.4, grime=0.6)
    M["paper"] = mat_worn_paint("paper_label", (0.62, 0.60, 0.52), rough=0.9, wear=0.0, grime=0.5,
                                scratch=0.0, bump=0.02)
    M["rubber"] = mat_plain("rubber", (0.016, 0.016, 0.016), rough=0.85)
    M["glass"] = mat_glass("screen_glass")
    M["lcd"] = mat_glass("lcd_glass", (0.006, 0.008, 0.004))
    M["lens"] = mat_lens("lamp_lens")
    M["led_off"] = mat_plain("led_off", (0.030, 0.012, 0.004), rough=0.2)
    M["led_pwr"] = mat_plain("led_power", (0.02, 0.2, 0.08), rough=0.2, emission=(0.1, 1.0, 0.4), strength=6.0)
    M["void"] = mat_plain("void", (0.004, 0.004, 0.004), rough=0.9)
    return M


# ---------------------------------------------------------------------------
# geometry helpers
# ---------------------------------------------------------------------------

def rect_pts(x, y, w, h, c=0.0):
    if c <= 0:
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    return [(x + c, y), (x + w - c, y), (x + w, y + c), (x + w, y + h - c),
            (x + w - c, y + h), (x + c, y + h), (x, y + h - c), (x, y + c)]


def circle_pts(cx, cy, r, n=28):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


class Device:
    def __init__(self, name, w, h, margin):
        self.name, self.w, self.h, self.m = name, w, h, margin
        self.coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(self.coll)
        self.cut_colls = {}
        self.meta = {
            "name": name,
            "image_size": [w + 2 * margin, h + 2 * margin],
            "chassis_rect": [margin, margin, w, h],
            "rects": {},
            "points": {},
        }

    # px -> blender
    def X(self, x):
        return (x - self.w / 2.0) * PX

    def Y(self, y):
        return (self.h / 2.0 - y) * PX

    def cutset(self, key):
        if key not in self.cut_colls:
            c = bpy.data.collections.new(f"{self.name}_cut_{key}")
            self.coll.children.link(c)
            self.cut_colls[key] = c
        return self.cut_colls[key]

    def rect(self, key, x, y, w, h):
        self.meta["rects"][key] = [x + self.m, y + self.m, w, h]

    def point(self, key, x, y):
        self.meta["points"][key] = [x + self.m, y + self.m]

    # --- geometry ---
    def prism(self, name, pts, z0, z1, mat=None, bevel=0.0, segs=2, cuts=(), cutter_for=None):
        bm = bmesh.new()
        verts = [bm.verts.new((self.X(x), self.Y(y), z0)) for x, y in pts]
        face = bm.faces.new(verts)
        ret = bmesh.ops.extrude_face_region(bm, geom=[face], use_keep_orig=True)
        top = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=(0.0, 0.0, z1 - z0), verts=top)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        me = bpy.data.meshes.new(f"{self.name}_{name}")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(me.name, me)

        if cutter_for is not None:
            self.cutset(cutter_for).objects.link(ob)
            ob.hide_render = True
            ob.display_type = "WIRE"
            return ob

        self.coll.objects.link(ob)
        if mat is not None:
            me.materials.append(mat)
        for key in cuts:
            mod = ob.modifiers.new(f"cut_{key}", "BOOLEAN")
            mod.operation = "DIFFERENCE"
            mod.operand_type = "COLLECTION"
            mod.collection = self.cutset(key)
            try:
                mod.solver = "EXACT"
            except TypeError:
                pass
        if bevel > 0:
            b = ob.modifiers.new("bevel", "BEVEL")
            b.width = bevel
            b.segments = segs
            b.limit_method = "ANGLE"
            b.angle_limit = math.radians(40)
        return ob

    def cut(self, key, pts, z_floor):
        return self.prism(f"cut_{key}_{len(self.cutset(key).objects)}", pts, z_floor, 1.0, cutter_for=key)

    def label(self, name, text, x, y, size, z, mat, align="LEFT", font=None):
        cu = bpy.data.curves.new(f"{self.name}_{name}", "FONT")
        cu.body = text
        cu.size = size * PX
        cu.extrude = 0.0012
        cu.align_x = align
        cu.align_y = "CENTER"
        if font is not None:
            cu.font = font
        cu.materials.append(mat)
        ob = bpy.data.objects.new(cu.name, cu)
        ob.location = (self.X(x), self.Y(y), z)
        self.coll.objects.link(ob)
        return ob

    def rivets(self, x0, x1, y, z_top, mat, step=40.0, r=2.6):
        n = int((x1 - x0) // step)
        for i in range(n + 1):
            x = x0 + i * step
            self.prism(f"rivet_{int(x)}_{int(y)}", circle_pts(x, y, r, 12), z_top - 0.01, z_top + 0.006, mat, bevel=0.0025, segs=2)

    def screw(self, x, y, z_top, mat, r=6.0):
        self.prism(f"screw_{x}_{y}", circle_pts(x, y, r, 20), z_top - 0.02, z_top + 0.012, mat,
                   bevel=0.005, segs=2, cuts=("screw",))
        ang = (hash((x, y)) % 180) * math.pi / 180.0
        dx, dy = math.cos(ang), math.sin(ang)
        px_, py_ = -dy, dx
        hw, hl = 1.2, r * 0.8
        pts = [(x - dx * hl - px_ * hw, y - dy * hl - py_ * hw), (x + dx * hl - px_ * hw, y + dy * hl - py_ * hw),
               (x + dx * hl + px_ * hw, y + dy * hl + py_ * hw), (x - dx * hl + px_ * hw, y - dy * hl + py_ * hw)]
        self.cut("screw", pts, z_top + 0.004)


# ---------------------------------------------------------------------------
# devices
# ---------------------------------------------------------------------------

def build_main_deck(M, font):
    """Main deck: indicator lamps left, wide terminal screen centre, status/aux bay right, heat gauge along the bottom."""
    W, H = 1860, 440
    d = Device("deck_main", W, H, margin=28)
    FACE = ("face",)

    # chassis + rubber corner bumpers
    d.prism("chassis", rect_pts(0, 0, W, H, 16), -0.30, 0.0, M["deck"], bevel=0.04, segs=3, cuts=FACE)
    for cx, cy in [(-5, -5), (W - 39, -5), (-5, H - 39), (W - 39, H - 39)]:
        d.prism(f"bumper_{cx}_{cy}", rect_pts(cx, cy, 44, 44, 12), -0.31, 0.012, M["rubber"], bevel=0.02, segs=3)

    # carry handles on both ends (also extra grab zones in Godot)
    for side, gx in (("l", -22), ("r", W + 8)):
        for py in (118, 298):
            d.prism(f"handle_post_{side}_{py}", rect_pts(gx - 2 if side == "l" else gx - 10, py, 26, 24, 4),
                    -0.2, 0.03, M["trim"], bevel=0.006)
        d.prism(f"handle_grip_{side}", rect_pts(gx, 108, 14, 224, 6), -0.05, 0.07, M["rubber"], bevel=0.012, segs=3)
        d.rect(f"handle_{side}", gx, 108, 14, 224)

    # raised panels (panel lines = gaps between them)
    d.prism("plate_left", rect_pts(14, 10, 278, 384, 6), 0.0, 0.02, M["plate"], bevel=0.012, cuts=FACE)
    d.prism("plate_mid", rect_pts(298, 8, 1164, 386, 4), 0.0, 0.012, M["trim"], bevel=0.008, cuts=FACE)
    d.prism("plate_right", rect_pts(1468, 10, 378, 384, 6), 0.0, 0.02, M["plate"], bevel=0.012, cuts=FACE)

    # --- centre: header strip + main screen ---
    d.cut("face", rect_pts(316, 16, 1128, 28, 3), -0.04)
    d.prism("header_lcd", rect_pts(318, 18, 1124, 24), -0.05, -0.035, M["lcd"])
    d.rect("header", 318, 18, 1124, 24)

    d.prism("screen_bezel", rect_pts(298, 46, 1164, 346, 8), 0.012, 0.045, M["trim"], bevel=0.012, segs=2, cuts=FACE)
    d.cut("face", rect_pts(308, 56, 1144, 326, 6), -0.14)
    d.prism("screen_glass", rect_pts(314, 62, 1132, 314, 4), -0.14, -0.11, M["glass"])
    d.rect("screen", 314, 62, 1132, 314)

    # --- left column: indicator lamps, RAM LEDs, hazard plate ---
    d.label("maker", "NS/DECK MK.II", 34, 30, 13, 0.02, M["stencil"], font=font)
    d.prism("led_power", circle_pts(146, 30, 5, 16), -0.01, 0.026, M["led_pwr"], bevel=0.004)
    d.point("led_power", 146, 30)
    for i in range(4):
        d.cut("face", rect_pts(160, 17 + i * 7, 112, 3), -0.06)

    lamp_names = ["lamp_scan", "lamp_lock", "lamp_ic", "lamp_aux"]
    for i, nm in enumerate(lamp_names):
        y = 54 + i * 68
        d.cut("face", rect_pts(34, y, 240, 58, 5), -0.03)
        d.prism(nm, rect_pts(38, y + 4, 232, 50, 4), -0.03, -0.012, M["lens"])
        d.rect(nm, 38, y + 4, 232, 50)

    d.label("ram", "RAM", 34, 336, 12, 0.02, M["stencil"], font=font)
    for i in range(8):
        x = 84 + i * 26
        d.prism(f"ram_{i}", circle_pts(x, 336, 6, 16), -0.01, 0.03, M["led_off"], bevel=0.004)
        d.point(f"ram_{i}", x, 336)

    d.prism("hazard", rect_pts(34, 358, 240, 26, 3), 0.02, 0.026, M["hazard"], bevel=0.003)

    for x, y in [(22, 22), (284, 22), (22, 382), (284, 382)]:
        d.screw(x, y, 0.02, M["trim"])

    # --- right column: status LCD, secondary screen, cartridge bay ---
    d.prism("status_bezel", rect_pts(1484, 12, 346, 60, 5), 0.02, 0.04, M["trim"], bevel=0.008, cuts=FACE)
    d.cut("face", rect_pts(1490, 18, 334, 48, 4), -0.05)
    d.prism("status_lcd", rect_pts(1494, 22, 326, 40, 2), -0.06, -0.04, M["lcd"])
    d.rect("status", 1494, 22, 326, 40)

    d.prism("screen2_bezel", rect_pts(1484, 70, 346, 182, 6), 0.02, 0.042, M["trim"], bevel=0.008, cuts=FACE)
    d.cut("face", rect_pts(1490, 76, 334, 170, 5), -0.10)
    d.prism("screen2_glass", rect_pts(1496, 82, 322, 158, 3), -0.10, -0.075, M["glass"])
    d.rect("screen2", 1496, 82, 322, 158)

    d.label("prg", "PRG BAY", 1492, 260, 11, 0.02, M["stencil"], font=font)
    for i in range(4):
        x = 1492 + i * 84
        d.cut("face", rect_pts(x, 272, 74, 106, 3), -0.16)
        d.prism(f"slot_floor_{i}", rect_pts(x, 272, 74, 106), -0.17, -0.155, M["void"])
        d.rect(f"cart_slot_{i}", x, 272, 74, 106)

    for x, y in [(1476, 22), (1838, 22), (1476, 382), (1838, 382)]:
        d.screw(x, y, 0.02, M["trim"])

    # rivet rows along the trim and the bottom rail
    d.rivets(60, 1800, 433, 0.0, M["deck"], step=58)

    # --- bottom: heat gauge ---
    d.cut("face", rect_pts(22, 402, 1816, 24, 3), -0.05)
    d.prism("heat_glass", rect_pts(26, 405, 1808, 18), -0.06, -0.035, M["lcd"])
    d.rect("heat", 26, 405, 1808, 18)
    for x in (8, 1852):
        d.screw(x, 220, 0.0, M["trim"], r=5)
    for i in range(11):
        tx = 22 + i * 1816 / 10.0
        d.cut("face", rect_pts(tx - 1.5, 396, 3, 5 if i % 5 else 6), -0.012)

    # --- top edge silhouette: cooling fins + antenna jack ---
    d.prism("fin_block", rect_pts(480, -12, 220, 26, 4), -0.22, 0.03, M["trim"], bevel=0.008)
    for i in range(9):
        d.prism(f"fin_{i}", rect_pts(492 + i * 22, -10, 10, 20, 2), 0.03, 0.065, M["deck"], bevel=0.004)
    d.prism("ant_jack", circle_pts(900, -4, 13, 24), -0.15, 0.05, M["trim"], bevel=0.008, cuts=("jack",))
    d.cut("jack", circle_pts(900, -4, 6, 16), 0.02)
    d.prism("ant_jack_core", circle_pts(900, -4, 6, 16), 0.0, 0.025, M["void"])

    # --- expansion port on the top edge (aux modules cable in here) ---
    d.prism("exp_port", rect_pts(1250, -18, 116, 34, 4), -0.26, 0.035, M["trim"], bevel=0.01, cuts=("port",))
    d.cut("port", rect_pts(1270, -10, 76, 14, 2), -0.02)
    d.prism("exp_port_floor", rect_pts(1270, -10, 76, 14), -0.04, -0.025, M["void"])
    d.point("exp_port_a", 1308, -3)

    # grab zones: anywhere on the bezel that is not a screen/lamp. Godot uses chassis_rect minus screens.
    return d


def build_aux_decrypt(M, font):
    """Hot-swap cryptanalysis module. Screen fits the decrypt puzzle (~390x280) at 1:1."""
    W, H = 480, 430
    d = Device("aux_decrypt", W, H, margin=40)
    FACE = ("face",)

    d.prism("body", rect_pts(0, 0, W, H, 14), -0.25, 0.0, M["khaki"], bevel=0.035, segs=3, cuts=FACE)

    # carry handle
    for x in (150, 304):
        d.prism(f"handle_post_{x}", rect_pts(x, -26, 26, 34, 4), -0.06, 0.05, M["trim"], bevel=0.008)
    d.prism("handle_bar", rect_pts(146, -38, 188, 18, 8), 0.0, 0.085, M["rubber"], bevel=0.012, segs=3)
    d.rect("handle", 146, -38, 188, 18)

    d.label("title", "DX-7  CRYPTANALYTIC UNIT", 34, 31, 14, 0.0, M["stencil"], font=font)
    d.label("serial", "S/N 0041-K", 446, 31, 10, 0.0, M["stencil"], align="RIGHT", font=font)

    d.prism("screen_bezel", rect_pts(12, 42, 456, 330, 8), 0.0, 0.035, M["trim"], bevel=0.01, segs=2, cuts=FACE)
    d.cut("face", rect_pts(22, 52, 436, 310, 6), -0.13)
    d.prism("screen_glass", rect_pts(28, 58, 424, 298, 4), -0.13, -0.10, M["glass"])
    d.rect("screen", 28, 58, 424, 298)

    for i in range(4):
        x = 28 + i * 54
        d.cut("face", rect_pts(x, 376, 46, 38, 4), -0.03)
        d.prism(f"key_{i}", rect_pts(x + 3, 379, 40, 32, 4), -0.03, 0.012, M["rubber"], bevel=0.008, segs=2)
        d.rect(f"key_{i}", x + 3, 379, 40, 32)

    for i in range(3):
        x = 262 + i * 22
        d.prism(f"led_{i}", circle_pts(x, 395, 6, 16), -0.01, 0.02, M["led_off"], bevel=0.004)
        d.point(f"led_{i}", x, 395)

    d.prism("knob", circle_pts(420, 395, 22, 32), 0.0, 0.06, M["trim"], bevel=0.01, segs=2, cuts=("knob",))
    d.cut("knob", rect_pts(418, 375, 4, 16), 0.045)
    d.point("knob", 420, 395)

    # cable socket on the left edge
    d.prism("cable_socket", rect_pts(-16, 66, 24, 50, 4), -0.2, 0.03, M["trim"], bevel=0.008)
    d.point("cable_port", -10, 91)

    for x, y in [(16, 16), (464, 16), (16, 414), (464, 414)]:
        d.screw(x, y, 0.0, M["trim"], r=5)
    d.label("warn", "LIVE KEYSPACE", 300, 422, 8, 0.0, M["stencil"])
    return d


def build_cartridge(M, font):
    """Program cartridge end-cap as seen in the deck's PRG BAY. Neutral grey so Godot can tint it."""
    W, H = 74, 106
    d = Device("cartridge", W, H, margin=6)
    d.prism("body", rect_pts(0, 0, W, H, 4), -0.10, 0.0, M["cart"], bevel=0.012, segs=2, cuts=("face",))
    for i in range(5):
        d.prism(f"grip_{i}", rect_pts(10, 8 + i * 5, 54, 2), 0.0, 0.008, M["cart"])
    d.cut("face", rect_pts(8, 36, 58, 58, 2), -0.01)
    d.prism("label", rect_pts(9, 37, 56, 56), -0.012, -0.004, M["paper"])
    d.rect("label", 9, 37, 56, 56)
    return d


# ---------------------------------------------------------------------------
# lighting / camera / render
# ---------------------------------------------------------------------------

def setup_world_and_lights(scene):
    world = bpy.data.worlds.new("world")
    scene.world = world
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    bg = world.node_tree.nodes.get("Background") if world.node_tree else None
    if bg is not None:
        bg.inputs[0].default_value = (0.05, 0.06, 0.06, 1.0)
        bg.inputs[1].default_value = 0.35

    def sun(name, direction, strength, angle_deg, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = strength
        ld.angle = math.radians(angle_deg)
        ld.color = color
        ob = bpy.data.objects.new(name, ld)
        scene.collection.objects.link(ob)
        ob.rotation_euler = Vector(direction).normalized().to_track_quat("Z", "Y").to_euler()
        return ob

    # key from top-left, fill from right, cool rim from below (screen-glow feel)
    sun("key", (-1.0, 1.2, 0.8), 4.6, 6, (1.0, 0.95, 0.88))
    sun("fill", (1.0, 0.1, 1.4), 0.45, 30, (0.85, 0.92, 1.0))
    sun("rim", (0.1, -1.0, 0.6), 0.5, 20, (0.6, 0.9, 0.85))


def setup_camera(scene):
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cd)
    cam.location = (0, 0, 5)
    cam.rotation_euler = (0, 0, 0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cd.clip_start = 0.1
    cd.clip_end = 20
    return cam


def try_set(obj, attr, *values):
    for v in values:
        try:
            setattr(obj, attr, v)
            return True
        except (TypeError, AttributeError, ValueError):
            continue
    return False


def enable_gpu(scene):
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for backend in ("OPTIX", "CUDA", "HIP", "ONEAPI", "METAL"):
            try:
                prefs.compute_device_type = backend
                prefs.get_devices()
                if any(dv.type == backend for dv in prefs.devices):
                    for dv in prefs.devices:
                        dv.use = True
                    scene.cycles.device = "GPU"
                    print(f"[deck] GPU rendering via {backend}")
                    return
            except TypeError:
                continue
    except Exception as e:  # noqa: BLE001
        print(f"[deck] GPU setup failed, using CPU: {e}")


def render_device(scene, dev, opts, all_devs):
    for other in all_devs:
        lc = bpy.context.view_layer.layer_collection.children[other.coll.name]
        lc.exclude = other is not dev

    iw, ih = dev.meta["image_size"]
    s = opts["scale"]
    scene.render.resolution_x = int(round(iw * s))
    scene.render.resolution_y = int(round(ih * s))
    scene.render.resolution_percentage = 100
    scene.camera.data.ortho_scale = max(iw, ih) * PX
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"

    passes = [("", "beauty")] if opts["fast"] else [("", "beauty"), ("_albedo", "albedo"), ("_normal", "normal")]
    for suffix, mode in passes:
        set_pass(mode)
        if mode == "beauty":
            scene.cycles.samples = opts["samples"]
            try_set(scene.cycles, "use_denoising", True)
            try_set(scene.view_settings, "view_transform", "AgX", "Filmic", "Standard")
            try_set(scene.view_settings, "look", "AgX - Medium High Contrast", "Medium High Contrast", "None")
        else:
            scene.cycles.samples = 8
            try_set(scene.cycles, "use_denoising", False)
            try_set(scene.view_settings, "view_transform", "Raw" if mode == "normal" else "Standard")
            try_set(scene.view_settings, "look", "None")
        path = os.path.join(OUT_DIR, f"{dev.name}{suffix}.png")
        scene.render.filepath = path
        print(f"[deck] rendering {path}")
        bpy.ops.render.render(write_still=True)
    set_pass("beauty")

    meta = dict(dev.meta)
    meta["render_scale"] = s
    with open(os.path.join(OUT_DIR, f"{dev.name}.json"), "w") as f:
        json.dump(meta, f, indent=2)


def main():
    opts = parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)
    scene = reset_scene()
    PASS_FLAGS["albedo"].clear()
    PASS_FLAGS["normal"].clear()

    font = None
    if os.path.exists(FONT_PATH):
        try:
            font = bpy.data.fonts.load(FONT_PATH)
        except RuntimeError:
            font = None

    M = build_materials()
    devs = [build_main_deck(M, font), build_aux_decrypt(M, font), build_cartridge(M, font)]
    setup_world_and_lights(scene)
    setup_camera(scene)
    scene.cycles.use_adaptive_sampling = True
    scene.render.use_persistent_data = True
    if opts["gpu"]:
        enable_gpu(scene)

    for dev in devs:
        if opts["only"] and dev.name not in opts["only"]:
            continue
        render_device(scene, dev, opts, devs)

    # leave every device visible in the saved .blend for inspection
    for dev in devs:
        bpy.context.view_layer.layer_collection.children[dev.coll.name].exclude = False
    if not opts["no_blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "deck_source.blend"))
    print("[deck] done ->", OUT_DIR)


if __name__ == "__main__":
    main()
