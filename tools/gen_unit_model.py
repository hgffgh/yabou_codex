"""
Procedurally builds a low-poly rigged mecha silhouette and exports it as a
glTF binary (.glb) matching DATA_DEFINITION.md section 9.1.1's model_scene
spec: feet at the origin (z=0 in Blender, which becomes Godot's y=0 after
the exporter's Z-up -> Y-up conversion), ~85 Blender units tall (the
STANDARD-size reference height; LIGHT/HEAVY are scaled 0.8x/1.35x at
runtime by the existing code, not baked in here), a 7-bone rigid rig
(root/torso/head/arm_l/arm_r/leg_l/leg_r, each mesh part 100% weighted to
exactly one bone -- no smooth skinning needed for rigid armor plates), and
five named actions (idle/move/attack/hit/destroyed) exported as separate
glTF animations via export_animation_mode='ACTIONS'.

Run headlessly:
  blender --background --python gen_unit_model.py -- <output.glb> [height]
"""
import bpy
import math
import sys

argv = sys.argv
args = argv[argv.index("--") + 1:] if "--" in argv else []
OUTPUT_PATH = args[0] if len(args) > 0 else "//out.glb"
HEIGHT = float(args[1]) if len(args) > 1 else 85.0

# ---- proportions (fractions of total height) ----
LEG_H = HEIGHT * 0.42
TORSO_H = HEIGHT * 0.30
HEAD_H = HEIGHT * 0.12
ARM_H = HEIGHT * 0.34
TORSO_W = HEIGHT * 0.22
TORSO_D = HEIGHT * 0.14
LIMB_R = HEIGHT * 0.045

HIP_Z = LEG_H
CHEST_Z = HIP_Z + TORSO_H
HEAD_TOP_Z = CHEST_Z + HEAD_H
ARM_X = TORSO_W * 0.62
LEG_X = TORSO_W * 0.28


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for data_block_collection in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions):
        for block in list(data_block_collection):
            if block.users == 0:
                data_block_collection.remove(block)


def build_rig():
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    rig = bpy.context.object
    rig.name = "Rig"
    eb = rig.data.edit_bones
    eb.remove(eb[0])

    def add_bone(name, head, tail, parent=None):
        b = eb.new(name)
        b.head = head
        b.tail = tail
        if parent:
            b.parent = eb[parent]
        return b

    add_bone("root", (0, 0, 0), (0, 0, HIP_Z * 0.15))
    add_bone("torso", (0, 0, HIP_Z), (0, 0, CHEST_Z), parent="root")
    add_bone("head", (0, 0, CHEST_Z), (0, 0, HEAD_TOP_Z), parent="torso")
    add_bone("arm_l", (ARM_X, 0, CHEST_Z), (ARM_X, 0, CHEST_Z - ARM_H), parent="torso")
    add_bone("arm_r", (-ARM_X, 0, CHEST_Z), (-ARM_X, 0, CHEST_Z - ARM_H), parent="torso")
    add_bone("leg_l", (LEG_X, 0, HIP_Z), (LEG_X, 0, 0), parent="root")
    add_bone("leg_r", (-LEG_X, 0, HIP_Z), (-LEG_X, 0, 0), parent="root")

    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def add_box_part(name, bone, size, center):
    # primitive_cube_add(size=1) already spans -0.5..+0.5 (edge length 1) on
    # each axis, so scaling by `size` directly yields final edge length
    # `size` -- scaling by size/2 (as this used to) halved every box's
    # actual dimensions, which is what caused Torso/Head to render half as
    # tall as their bone placement assumed and visibly float apart.
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    vg = obj.vertex_groups.new(name=bone)
    vg.add(range(len(obj.data.vertices)), 1.0, 'REPLACE')
    return obj


def add_cylinder_part(name, bone, radius, depth, center):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=8, location=center)
    obj = bpy.context.object
    obj.name = name
    vg = obj.vertex_groups.new(name=bone)
    vg.add(range(len(obj.data.vertices)), 1.0, 'REPLACE')
    return obj


def build_mesh(rig):
    parts = []
    parts.append(add_box_part("Torso", "torso", (TORSO_W, TORSO_D, TORSO_H), (0, 0, (HIP_Z + CHEST_Z) / 2.0)))
    parts.append(add_box_part("Head", "head", (TORSO_W * 0.5, TORSO_D * 0.7, HEAD_H), (0, 0, (CHEST_Z + HEAD_TOP_Z) / 2.0)))
    parts.append(add_cylinder_part("ArmL", "arm_l", LIMB_R, ARM_H, (ARM_X, 0, CHEST_Z - ARM_H / 2.0)))
    parts.append(add_cylinder_part("ArmR", "arm_r", LIMB_R, ARM_H, (-ARM_X, 0, CHEST_Z - ARM_H / 2.0)))
    parts.append(add_cylinder_part("LegL", "leg_l", LIMB_R * 1.15, LEG_H, (LEG_X, 0, HIP_Z / 2.0)))
    parts.append(add_cylinder_part("LegR", "leg_r", LIMB_R * 1.15, LEG_H, (-LEG_X, 0, HIP_Z / 2.0)))

    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = "Body"

    modifier = body.modifiers.new(name="Armature", type='ARMATURE')
    modifier.object = rig
    body.parent = rig

    mat = bpy.data.materials.new(name="HullBase")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.72, 0.74, 0.78, 1.0)
        bsdf.inputs["Metallic"].default_value = 0.6
        bsdf.inputs["Roughness"].default_value = 0.45
    body.data.materials.append(mat)
    return body


def keyframe_pose(rig, action_name, frames, use_fake_user=True):
    """frames: list of (frame_number, {bone_name: (rx, ry, rz) in radians})."""
    action = bpy.data.actions.new(name=action_name)
    action.use_fake_user = use_fake_user
    rig.animation_data_create()
    rig.animation_data.action = action

    for bone in rig.pose.bones:
        bone.rotation_mode = 'XYZ'

    for frame, pose in frames:
        bpy.context.scene.frame_set(frame)
        for bone_name, euler in pose.items():
            pb = rig.pose.bones[bone_name]
            pb.rotation_euler = euler
            pb.keyframe_insert(data_path="rotation_euler", frame=frame)
    bpy.context.scene.frame_set(0)


def build_animations(rig):
    D = math.radians

    keyframe_pose(rig, "idle", [
        (1, {"torso": (0, 0, 0), "arm_l": (D(4), 0, 0), "arm_r": (D(4), 0, 0)}),
        (30, {"torso": (D(2), 0, 0), "arm_l": (D(8), 0, 0), "arm_r": (D(8), 0, 0)}),
        (60, {"torso": (0, 0, 0), "arm_l": (D(4), 0, 0), "arm_r": (D(4), 0, 0)}),
    ])

    keyframe_pose(rig, "move", [
        (1, {"leg_l": (D(-25), 0, 0), "leg_r": (D(25), 0, 0), "arm_l": (D(20), 0, 0), "arm_r": (D(-20), 0, 0)}),
        (12, {"leg_l": (D(25), 0, 0), "leg_r": (D(-25), 0, 0), "arm_l": (D(-20), 0, 0), "arm_r": (D(20), 0, 0)}),
        (24, {"leg_l": (D(-25), 0, 0), "leg_r": (D(25), 0, 0), "arm_l": (D(20), 0, 0), "arm_r": (D(-20), 0, 0)}),
    ])

    keyframe_pose(rig, "attack", [
        (1, {"arm_r": (0, 0, 0)}),
        (6, {"arm_r": (D(-110), 0, D(15))}),
        (10, {"arm_r": (D(-130), 0, D(-10))}),
        (20, {"arm_r": (0, 0, 0)}),
    ])

    keyframe_pose(rig, "hit", [
        (1, {"torso": (0, 0, 0)}),
        (4, {"torso": (D(-18), 0, D(6))}),
        (12, {"torso": (0, 0, 0)}),
    ])

    keyframe_pose(rig, "destroyed", [
        (1, {"root": (0, 0, 0), "torso": (0, 0, 0)}),
        (18, {"root": (D(78), 0, D(20)), "torso": (D(10), 0, 0)}),
        (30, {"root": (D(85), 0, D(24)), "torso": (D(14), 0, 0)}),
    ])

    rig.animation_data.action = None


def main():
    clear_scene()
    rig = build_rig()
    build_mesh(rig)
    build_animations(rig)

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_PATH,
        export_format='GLB',
        use_selection=True,
        export_animations=True,
        export_animation_mode='ACTIONS',
        export_apply=True,
    )
    print("EXPORTED:", OUTPUT_PATH)


main()
