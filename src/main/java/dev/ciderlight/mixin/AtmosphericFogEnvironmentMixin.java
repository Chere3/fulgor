package dev.ciderlight.mixin;

import dev.ciderlight.backend.MetalShaders;
import net.minecraft.client.Camera;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.fog.FogData;
import net.minecraft.client.renderer.fog.environment.AtmosphericFogEnvironment;
import org.joml.Vector3f;
import org.joml.Vector3fc;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** The Nether's air with shaders on: a pale, warm grey haze that reaches the render distance, not a near dark wall. */
@Mixin(AtmosphericFogEnvironment.class)
public class AtmosphericFogEnvironmentMixin {
    @Inject(method = "getBaseColor", at = @At("RETURN"), cancellable = true)
    private void ciderlight$netherHaze(final ClientLevel level, final Camera camera, final int renderDistance, final float partialTick,
                                      final CallbackInfoReturnable<Vector3fc> cir) {
        if (MetalShaders.netherHaze(level)) {
            // Each biome keeps a part of its own fog colour.
            cir.setReturnValue(new Vector3f(cir.getReturnValue()).lerp(new Vector3f(0.60F, 0.47F, 0.42F), 0.85F));
        }
    }

    @Inject(method = "setupFog", at = @At("RETURN"))
    private void ciderlight$netherReach(final FogData fog, final Camera camera, final ClientLevel level, final float distance,
                                       final DeltaTracker delta, final CallbackInfo ci) {
        if (MetalShaders.netherHaze(level)) {
            fog.environmentalStart = 0.0F;
            fog.environmentalEnd = Math.max(fog.environmentalEnd, distance);
        }
    }
}
