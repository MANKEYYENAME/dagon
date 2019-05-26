/*
Copyright (c) 2019 Timur Gafarov

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
import dagon.render.framebuffer;
import dagon.render.shadowstage;
import dagon.render.framebuffer_rgba16f;
import dagon.game.renderer;

class DeferredRenderer: Renderer
{
    ShadowStage stageShadow;
    DeferredGeometryStage stageGeom;
    DeferredEnvironmentStage stageEnvironment;
    DeferredLightStage stageLight;
    DeferredDebugOutputStage stageDebug;
    
    DebugOutputMode outputMode = DebugOutputMode.Radiance;
    
    this(EventManager eventManager, Owner owner)
    {
        super(eventManager, owner);
        
        stageShadow = New!ShadowStage(pipeline);
        
        stageGeom = New!DeferredGeometryStage(pipeline);
        stageGeom.view = view;
        
        stageEnvironment = New!DeferredEnvironmentStage(pipeline, stageGeom);
        stageEnvironment.view = view;
        
        stageLight = New!DeferredLightStage(pipeline, stageGeom);
        stageLight.view = view;
        
        stageDebug = New!DeferredDebugOutputStage(pipeline, stageGeom);
        stageDebug.view = view;
        stageDebug.active = false;
        
        outputBuffer = New!FramebufferRGBA16f(eventManager.windowWidth, eventManager.windowHeight, this);
        stageEnvironment.outputBuffer = outputBuffer;
        stageLight.outputBuffer = outputBuffer;
        stageDebug.outputBuffer = outputBuffer;
    }
    
    override void scene(Scene s)
    {
        stageShadow.group = s.spatial;
        stageShadow.lightGroup = s.lights;
        stageGeom.group = s.spatialOpaque;
        stageLight.group = s.lights;
        
        stageGeom.state.environment = s.environment;
        stageEnvironment.state.environment = s.environment;
        stageLight.state.environment = s.environment;
        stageDebug.state.environment = s.environment;
    }
    
    override void update(Time t)
    {        
        stageShadow.camera = activeCamera;
        stageDebug.active = (outputMode != DebugOutputMode.Radiance);
        stageDebug.outputMode = outputMode;
        super.update(t);
    }
    
    override void setViewport(uint x, uint y, uint w, uint h)
    {
        super.setViewport(x, y, w, h);
        
        outputBuffer.resize(view.width, view.height);
    }
}
