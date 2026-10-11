package dev.ciderlight.backend;

import com.mojang.renderpearl.api.textures.GpuTexture;

/**
 * The world drawn at a fraction of the window's resolution (Quality.renderScale) and stretched over it before the HUD
 * is drawn, which stays sharp. GameRendererMixin swaps the smaller target in for the world and calls upscale after.
 */
public final class RenderScale {
    private RenderScale() {
    }

    /** The fraction in each direction, or 1 when the game is not running on Ciderlight's backend. */
    public static float scale() {
        MetalDevice device = MetalDevice.current;
        return device == null ? 1.0F : device.shaders().renderScale();
    }

    /**
     * Set by GameRendererMixin while it creates or resizes the world's own render target, on the render thread:
     * MetalTexture recognises that target's colour texture by it (labels only reach the backend when debugging).
     */
    public static boolean creatingWorldTarget;

    /**
     * With shaders on the world is drawn into a floating-point target of its own, at any scale, so lit colours can
     * exceed 1 until the final pass (MetalShaders.upscale) tone-maps them into the window's 8-bit target.
     */
    public static boolean hdr() {
        return MetalDevice.current != null && MetalShaders.ENABLED;
    }

    /** Whether the world is drawn into a target of its own, not the window's. */
    public static boolean separate() {
        return hdr() || scale() < 1.0F;
    }

    public static int scaled(final int size) {
        return Math.max(1, Math.round(size * scale()));
    }

    /** Stretches what was drawn into `source` over `target`, which is `width` by `height`. */
    public static void upscale(final GpuTexture source, final GpuTexture target, final int width, final int height) {
        MetalDevice device = MetalDevice.current;
        if (device != null) {
            device.shaders().upscale(device.encoder().frame(), ((MetalTexture)source).handle(), ((MetalTexture)target).handle(), width, height);
        }
    }
}
