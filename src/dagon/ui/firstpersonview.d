/*
Copyright (c) 2017-2020 Timur Gafarov

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

module dagon.ui.firstpersonview;

import std.math;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;
import dlib.math.transformation;
import dlib.math.utils;

import dagon.core.event;
import dagon.core.keycodes;
import dagon.core.time;
import dagon.graphics.entity;

class FirstPersonViewComponent: EntityComponent
{
    int prevMouseX = 0;
    int prevMouseY = 0;
    
    float pitch = 0.0f;
    float turn = 0.0f;

    float mouseSensibility = 0.1f;
    
    bool active = true;
    
    float pitchLimitMax = 60.0f;
    float pitchLimitMin = -60.0f;
    
    this(EventManager em, Entity e)
    {
        super(em, e);
        reset();
    }
    
    void reset()
    {
        pitch = 0.0f;
        turn = 0.0f;
        eventManager.setMouseToCenter();
        prevMouseX = eventManager.mouseX;
        prevMouseY = eventManager.mouseY;
    }
    
    override void update(Time time)
    {
        processEvents();
        
        if (active)
        {
            float turn_m =  (eventManager.mouseX - prevMouseX) * mouseSensibility;
            float pitch_m = (eventManager.mouseY - prevMouseY) * mouseSensibility;
            
            pitch -= pitch_m;
            turn -= turn_m;
            
            if (pitch > pitchLimitMax)
            {
                pitch = pitchLimitMax;
            }
            else if (pitch < pitchLimitMin)
            {
                pitch = pitchLimitMin;
            }
            
            eventManager.setMouse(prevMouseX, prevMouseY);
        }
        
        auto rotPitch = rotationQuaternion(Vector3f(1.0f,0.0f,0.0f), degtorad(pitch));
        auto rotTurn = rotationQuaternion(Vector3f(0.0f,1.0f,0.0f), degtorad(turn));
        
        Quaternionf q = rotTurn * rotPitch;
        
        entity.transformation =
            translationMatrix(entity.position) *
            q.toMatrix4x4 *
            scaleMatrix(entity.scaling);
        
        entity.invTransformation = entity.transformation.inverse;
        
        if (entity.parent)
        {
            entity.absoluteTransformation = entity.parent.absoluteTransformation * entity.transformation;
            entity.invAbsoluteTransformation = entity.invTransformation * entity.parent.invAbsoluteTransformation;
            entity.prevAbsoluteTransformation = entity.parent.prevAbsoluteTransformation * entity.prevTransformation;
        }
        else
        {
            entity.absoluteTransformation = entity.transformation;
            entity.invAbsoluteTransformation = entity.invTransformation;
            entity.prevAbsoluteTransformation = entity.prevTransformation;
        }
    }
}
