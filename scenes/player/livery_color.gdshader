shader_type canvas_item;
// TRUE multiply blending against the LIVE framebuffer (2026-07-14). This shader used to sample
// hint_screen_texture and output the darkened screen — but Godot's AUTOMATIC backbuffer copy is
// taken ONCE per frame, at the FIRST screen-reading item drawn (the exact stale-copy behavior
// ship_visual.gd works around with an explicit per-ship BackBufferCopy). In combat every livery
// after the first sampled a copy missing its own hull, so the decal showed the BACKGROUND through
// the ship. Over the dark parallax backdrop that read as dark paint (invisible artifact); the
// asteroid strongholds exposed it — bright rocks share the gameplay canvas at ground z, so the
// stale sample showed the rock THROUGH the ship ("transparent livery", player included, since the
// buildings' ground-z liveries drew first and claimed the frame's one copy).
// blend_mul needs no screen texture and no copies: the GPU blender multiplies the decal into
// whatever is REALLY under it, every item, every frame. GOTCHA: blend_mul is dst * src.rgb with NO
// alpha term — the NEUTRAL value is WHITE, not transparent (emitting rgb=0 in the clear regions
// multiplied the whole sprite quad to a black box). So the fragment lerps the multiplier from 1.0
// (identity, outside the decal) toward the tint by opacity*alpha: dst*mix(1.0, tint, opacity*a) —
// identical to the old mix(screen, screen*tint, opacity) look, order-correct, and HDR-safe.
render_mode blend_mul;

// 1. Color picker for the darkening tint
uniform vec4 tint_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);

// 2. Opacity slider from 0.0 (no effect) to 1.0 (full multiply)
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

// 3. Master visibility (1 = shown, 0 = gone). Scales the decal's blend weight toward identity
//    (multiply-by-1 = no effect), so enemy_base's death-fade tweening this 1→0 still dissolves
//    the decal with the unit. Defaults 1.0 (the player + living enemies never touch it).
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    // The sprite's texture is the decal's shape mask.
    vec4 sprite_tex = texture(TEXTURE, UV);
    float a = sprite_tex.a * fade;

    // DISCARD the transparent surround instead of emitting an "identity" multiplier: a multiplied
    // fragment still passes through the canvas final-modulate/grade, so an emitted 1.0 lands
    // fractionally below 1.0 and the whole quad reads as a faint dark box. A discarded fragment
    // writes nothing — the pixels outside the decal are untouched EXACTLY. (Pixel art + nearest
    // filter = binary alpha, so the cut is clean.)
    if (a < 0.001) {
        discard;
    }

    // Multiply factor inside the decal: identity blended toward the tint by opacity*alpha.
    // a=1 → dst*mix(1,tint,opacity) (the full 80% tint-multiply); partial alpha interpolates.
    // Alpha 1.0 keeps dst alpha through the multiply.
    COLOR = vec4(mix(vec3(1.0), tint_color.rgb, opacity * a), 1.0);
}
