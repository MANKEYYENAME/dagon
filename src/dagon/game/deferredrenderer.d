/*
Copyright (c) 2019-2020 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.game.deferredrenderer;

import dlib.core.memory;
import dlib.core.ownership;

import dagon.core.event;
import dagon.core.time;
import dagon.resource.scene;
import dagon.render.deferred;
import dagon.render.gbuffer;
import dagon.render.view;
import dagon.render.framebuffer;
import dagon.render.shadowpass;
import dagon.postproc.filterpass;
import dagon.postproc.shaders.denoise;
import dagon.game.renderer;

class DeferredRenderer: Renderer
{
    GBuffer gbuffer;

    DenoiseShader denoiseShader;

    ShadowPass passShadow;
    DeferredClearPass passClear;
    DeferredBackgroundPass passBackground;
    DeferredGeometryPass passStaticGeometry;
    DeferredDecalPass passDecals;
    DeferredGeometryPass passDynamicGeometry;
    DeferredOcclusionPass passOcclusion;
    FilterPass passOcclusionDenoise;
    DeferredEnvironmentPass passEnvironment;
    DeferredLightPass passLight;
    DeferredParticlesPass passParticles;
    DeferredForwardPass passForward;
    DeferredDebugOutputPass passDebug;

    RenderView occlusionView;
    Framebuffer occlusionNoisyBuffer;
    Framebuffer occlusionBuffer;

    DebugOutputMode outputMode = DebugOutputMode.Radiance;

    bool _ssaoEnabled = true;

    int ssaoSamples = 10;
    float ssaoRadius = 0.2f;
    float ssaoPower = 7.0f;
    float ssaoDenoise = 1.0f;
    
    float occlusionBufferDetail = 0.75f;

    this(EventManager eventManager, Owner owner)
    {
        super(eventManager, owner);

        occlusionView = New!RenderView(0, 0, cast(uint)(view.width * occlusionBufferDetail), cast(uint)(view.height * occlusionBufferDetail), this);
        occlusionNoisyBuffer = New!Framebuffer(occlusionView.width, occlusionView.height, FrameBufferFormat.R8, false, this);
        occlusionBuffer = New!Framebuffer(occlusionView.width, occlusionView.height, FrameBufferFormat.R8, false, this);

        // HDR buffer
        auto radianceBuffer = New!Framebuffer(eventManager.windowWidth, eventManager.windowHeight, FrameBufferFormat.RGBA16F, true, this);
        outputBuffer = radianceBuffer;

        gbuffer = New!GBuffer(view.width, view.height, radianceBuffer, this);

        passShadow = New!ShadowPass(pipeline);

        passClear = New!DeferredClearPass(pipeline, gbuffer);

        passBackground = New!DeferredBackgroundPass(pipeline, gbuffer);
        passBackground.view = view;

        passStaticGeometry = New!DeferredGeometryPass(pipeline, gbuffer);
        passStaticGeometry.view = view;

        passDecals = New!DeferredDecalPass(pipeline, gbuffer);
        passDecals.view = view;

        passDynamicGeometry = New!DeferredGeometryPass(pipeline, gbuffer);
        passDynamicGeometry.view = view;

        passOcclusion = New!DeferredOcclusionPass(pipeline, gbuffer);
        passOcclusion.view = occlusionView;
        passOcclusion.outputBuffer = occlusionNoisyBuffer;

        denoiseShader = New!DenoiseShader(this);
        passOcclusionDenoise = New!FilterPass(pipeline, denoiseShader);
        passOcclusionDenoise.view = occlusionView;
        passOcclusionDenoise.inputBuffer = occlusionNoisyBuffer;
        passOcclusionDenoise.outputBuffer = occlusionBuffer;

        passEnvironment = New!DeferredEnvironmentPass(pipeline, gbuffer);
        passEnvironment.view = view;
        passEnvironment.outputBuffer = radianceBuffer;
        passEnvironment.occlusionBuffer = occlusionBuffer;

        passLight = New!DeferredLightPass(pipeline, gbuffer);
        passLight.view = view;
        passLight.outputBuffer = radianceBuffer;
        passLight.occlusionBuffer = occlusionBuffer;

        passForward = New!DeferredForwardPass(pipeline, gbuffer);
        passForward.view = view;
        passForward.outputBuffer = radianceBuffer;

        passParticles = New!DeferredParticlesPass(pipeline, gbuffer);
        passParticles.view = view;
        passParticles.outputBuffer = radianceBuffer;
        passParticles.gbuffer = gbuffer;

        passDebug = New!DeferredDebugOutputPass(pipeline, gbuffer);
        passDebug.view = view;
        passDebug.active = false;
        passDebug.outputBuffer = radianceBuffer;
        passDebug.occlusionBuffer = occlusionBuffer;
    }

    void ssaoEnabled(bool mode) @property
    {
        _ssaoEnabled = mode;
        passOcclusion.active = mode;
        passOcclusionDenoise.active = mode;
        if (_ssaoEnabled)
        {
            passEnvironment.occlusionBuffer = occlusionBuffer;
            passLight.occlusionBuffer = occlusionBuffer;
        }
        else
        {
            passEnvironment.occlusionBuffer = null;
            passLight.occlusionBuffer = null;
        }
    }

    bool ssaoEnabled() @property
    {
        return _ssaoEnabled;
    }

    override void scene(Scene s)
    {
        passShadow.group = s.spatial;
        passShadow.lightGroup = s.lights;
        passBackground.group = s.background;
        passStaticGeometry.group = s.spatialOpaqueStatic;
        passDecals.group = s.decals;
        passDynamicGeometry.group = s.spatialOpaqueDynamic;
        passLight.groupSunLights = s.sunLights;
        passLight.groupAreaLights = s.areaLights;
        passForward.group = s.spatialTransparent;
        passParticles.group = s.spatial;
        
        passBackground.state.environment = s.environment;
        passStaticGeometry.state.environment = s.environment;
        passDecals.state.environment = s.environment;
        passDynamicGeometry.state.environment = s.environment;
        passEnvironment.state.environment = s.environment;
        passLight.state.environment = s.environment;
        passForward.state.environment = s.environment;
        passParticles.state.environment = s.environment;
        passDebug.state.environment = s.environment;
    }

    override void update(Time t)
    {
        passShadow.camera = activeCamera;
        passDebug.active = (outputMode != DebugOutputMode.Radiance);
        passDebug.outputMode = outputMode;

        passOcclusion.ssaoShader.samples = ssaoSamples;
        passOcclusion.ssaoShader.radius = ssaoRadius;
        passOcclusion.ssaoShader.power = ssaoPower;
        denoiseShader.factor = ssaoDenoise;

        super.update(t);
    }

    override void setViewport(uint x, uint y, uint w, uint h)
    {
        super.setViewport(x, y, w, h);

        outputBuffer.resize(view.width, view.height);
        gbuffer.resize(view.width, view.height);

        occlusionView.resize(cast(uint)(view.width * occlusionBufferDetail), cast(uint)(view.height * occlusionBufferDetail));
        occlusionNoisyBuffer.resize(occlusionView.width, occlusionView.height);
        occlusionBuffer.resize(occlusionView.width, occlusionView.height);
    }
}
