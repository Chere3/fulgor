package dev.ciderlight.mixin;

import dev.ciderlight.backend.MetalShaders;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.Hud;
import net.minecraft.world.entity.Entity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** With shaders on the final pass has its own soft vignette; the game's darkens the corners heavily in dim places. */
@Mixin(Hud.class)
public class HudMixin {
    @Inject(method = "extractVignette", at = @At("HEAD"), cancellable = true)
    private void ciderlight$noVignette(final GuiGraphicsExtractor graphics, final Entity camera, final CallbackInfo ci) {
        if (MetalShaders.softVignette()) {
            ci.cancel();
        }
    }
}
