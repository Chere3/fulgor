package dev.ciderlight.mixin;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.math.Axis;
import com.mojang.renderpearl.api.commands.RenderPass;
import dev.ciderlight.backend.MetalShaders;
import net.minecraft.client.renderer.SkyRenderer;
import net.minecraft.world.level.MoonPhase;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Tilts the path the sun, moon and stars take across the sky (MetalShaders.sunTilt), so the discs stay where the
 * light and the shadows say they are.
 */
@Mixin(SkyRenderer.class)
public class SkyRendererMixin {
    /** The sky shader draws a round sun of its own (sky.metal) with the soft clouds. */
    @Inject(method = "renderSun", at = @At("HEAD"), cancellable = true)
    private void ciderlight$roundSun(final RenderPass renderPass, final float rainBrightness, final PoseStack poseStack, final CallbackInfo ci) {
        if (MetalShaders.softClouds()) {
            ci.cancel();
        }
    }

    @Inject(
        method = "renderSunMoonAndStars",
        at = @At(value = "INVOKE", target = "Lcom/mojang/blaze3d/vertex/PoseStack;rotateDegrees(Lcom/mojang/math/Axis;F)V", ordinal = 0, shift = At.Shift.AFTER)
    )
    private void ciderlight$tiltPath(
        final RenderPass renderPass, final PoseStack poseStack, final float sunAngle, final float moonAngle, final float starAngle,
        final MoonPhase moonPhase, final float rainBrightness, final float starBrightness, final CallbackInfo ci
    ) {
        float tilt = MetalShaders.sunTilt();
        if (tilt != 0.0F) {
            // Here the path's east-west axis is the local Z axis (the pose was just turned by -90 degrees around Y).
            poseStack.rotate(Axis.ZP, -tilt);
        }
    }
}
