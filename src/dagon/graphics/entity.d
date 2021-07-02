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

module dagon.graphics.entity;

import std.math;

import dlib.core.ownership;
import dlib.container.array;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;
import dlib.math.transformation;
import dlib.math.utils;
import dlib.geometry.aabb;

import dagon.core.bindings;
import dagon.core.event;
import dagon.core.time;
import dagon.graphics.updateable;
import dagon.graphics.drawable;
import dagon.graphics.mesh;
import dagon.graphics.terrain;
import dagon.graphics.material;
import dagon.graphics.tween;

class EntityManager: Owner
{
    Array!Entity entities;

    this(Owner owner)
    {
        super(owner);
    }

    void addEntity(Entity e)
    {
        entities.append(e);
    }

    ~this()
    {
        entities.free();
    }
}

enum EntityLayer: int
{
    Background = 0,
    Spatial = 1,
    Foreground = 2
}

class Entity: Owner, Updateable
{
   public:
    EntityLayer layer = EntityLayer.Spatial;
    bool visible = true;
    bool castShadow = true;
    bool solid = false;
    bool dynamic = true;
    bool decal = false;
    float opacity = 1.0f;
    float blurMask = 1.0f;

    EntityManager manager;

    Entity parent = null;
    Array!Entity children;

    Array!EntityComponent components;
    Array!Tween tweens;

    Drawable drawable;
    Material material;

    Vector3f position;
    Quaternionf rotation;
    Vector3f scaling;

    Matrix4x4f transformation;
    Matrix4x4f invTransformation;

    Matrix4x4f absoluteTransformation;
    Matrix4x4f invAbsoluteTransformation;

    Matrix4x4f prevTransformation;
    Matrix4x4f prevAbsoluteTransformation;

    Vector3f boundingBoxSize;

   protected:
    AABB aabb;

   public:
    this(Owner owner)
    {
        super(owner);

        EntityManager mngr = cast(EntityManager)owner;
        if (mngr)
        {
            manager = mngr;
            manager.addEntity(this);
        }

        position = Vector3f(0, 0, 0);
        rotation = Quaternionf.identity;
        scaling = Vector3f(1, 1, 1);

        transformation = Matrix4x4f.identity;
        invTransformation = Matrix4x4f.identity;

        absoluteTransformation = Matrix4x4f.identity;
        invAbsoluteTransformation = Matrix4x4f.identity;

        prevTransformation = Matrix4x4f.identity;
        prevAbsoluteTransformation = Matrix4x4f.identity;

        tweens.reserve(10);

        boundingBoxSize = Vector3f(1.0f, 1.0f, 1.0f);
        aabb = AABB(position, boundingBoxSize);
    }

    void setParent(Entity e)
    {
        if (parent)
            parent.removeChild(this);

        parent = e;
        parent.addChild(this);
    }

    void addChild(Entity e)
    {
        if (e.parent)
            e.parent.removeChild(e);
        children.append(e);
        e.parent = this;
    }

    void removeChild(Entity e)
    {
        children.removeFirst(e);
    }

    void addComponent(EntityComponent ec)
    {
        components.append(ec);
    }

    void removeComponent(EntityComponent ec)
    {
        components.removeFirst(ec);
    }

    void updateTransformation()
    {
        prevTransformation = transformation;

        transformation =
            translationMatrix(position) *
            rotation.toMatrix4x4 *
            scaleMatrix(scaling);

        invTransformation = transformation.inverse;

        if (parent)
        {
            absoluteTransformation = parent.absoluteTransformation * transformation;
            invAbsoluteTransformation = invTransformation * parent.invAbsoluteTransformation;
            prevAbsoluteTransformation = parent.prevAbsoluteTransformation * prevTransformation;
        }
        else
        {
            absoluteTransformation = transformation;
            invAbsoluteTransformation = invTransformation;
            prevAbsoluteTransformation = prevTransformation;
        }

        aabb = AABB(absoluteTransformation.translation, boundingBoxSize);
    }

    void updateTransformationDeep()
    {
        if (parent)
            parent.updateTransformationDeep();
        updateTransformation();
    }

    void update(Time t)
    {
        foreach(i, ref tween; tweens.data)
        {
            tween.update(t.delta);
        }

        updateTransformation();

        foreach(c; components)
        {
            c.update(t);
        }
    }

    void release()
    {
        if (parent)
            parent.removeChild(this);

        for (size_t i = 0; i < children.data.length; i++)
            children.data[i].parent = null;

        children.free();
        components.free();
        tweens.free();
    }

    Vector3f positionAbsolute()
    {
        return absoluteTransformation.translation;
    }

    Quaternionf rotationAbsolute()
    {
        if (parent)
            return parent.rotationAbsolute * rotation;
        else
            return rotation;
    }

    void translate(Vector3f v)
    {
        position += v;
    }

    void translate(float vx, float vy, float vz)
    {
        position += Vector3f(vx, vy, vz);
    }

    void move(float speed)
    {
        position += transformation.forward * speed;
    }

    void moveToPoint(Vector3f p, float speed)
    {
        Vector3f dir = (p - position).normalized;
        float d = distance(p, position);
        if (d > speed)
            position += dir * speed;
        else
            position += dir * d;
    }

    void strafe(float speed)
    {
        position += transformation.right * speed;
    }

    void lift(float speed)
    {
        position += transformation.up * speed;
    }

    void angles(Vector3f v)
    {
        rotation =
            rotationQuaternion!float(Axis.x, degtorad(v.x)) *
            rotationQuaternion!float(Axis.y, degtorad(v.y)) *
            rotationQuaternion!float(Axis.z, degtorad(v.z));
    }

    void rotate(Vector3f v)
    {
        auto r =
            rotationQuaternion!float(Axis.x, degtorad(v.x)) *
            rotationQuaternion!float(Axis.y, degtorad(v.y)) *
            rotationQuaternion!float(Axis.z, degtorad(v.z));
        rotation *= r;
    }

    void rotate(float x, float y, float z)
    {
        rotate(Vector3f(x, y, z));
    }

    void pitch(float angle)
    {
        rotation *= rotationQuaternion!float(Axis.x, degtorad(angle));
    }

    void turn(float angle)
    {
        rotation *= rotationQuaternion!float(Axis.y, degtorad(angle));
    }

    void roll(float angle)
    {
        rotation *= rotationQuaternion!float(Axis.z, degtorad(angle));
    }

    void scale(float s)
    {
        scaling += Vector3f(s, s, s);
    }

    void scale(Vector3f s)
    {
        scaling += s;
    }

    void scaleX(float s)
    {
        scaling.x += s;
    }

    void scaleY(float s)
    {
        scaling.y += s;
    }

    void scaleZ(float s)
    {
        scaling.z += s;
    }

    Vector3f direction() @property
    {
        return transformation.forward;
    }

    Vector3f right() @property
    {
        return transformation.right;
    }

    Vector3f up() @property
    {
        return transformation.up;
    }

    Vector3f directionAbsolute() @property
    {
        return absoluteTransformation.forward;
    }

    Vector3f rightAbsolute() @property
    {
        return absoluteTransformation.right;
    }

    Vector3f upAbsolute() @property
    {
        return absoluteTransformation.up;
    }

    Tween* getInactiveTween()
    {
        Tween* inactiveTween = null;
        foreach(i, ref t; tweens.data)
        {
            if (!t.active)
            {
                inactiveTween = &tweens.data[i];
                break;
            }
        }
        return inactiveTween;
    }

    Tween* moveFromTo(Vector3f pointFrom, Vector3f pointTo, double duration, Easing easing = Easing.Linear)
    {
        Tween* existingTween = getInactiveTween();

        if (existingTween)
        {
            *existingTween = Tween(this, TweenType.Position, pointFrom, pointTo, duration, easing);
            return existingTween;
        }
        else
        {
            Tween t = Tween(this, TweenType.Position, pointFrom, pointTo, duration, easing);
            tweens.append(t);
            return &tweens.data[$-1];
        }
    }

    Tween* rotateFromTo(Vector3f anglesFrom, Vector3f anglesTo, double duration, Easing easing = Easing.Linear)
    {
        Tween* existingTween = getInactiveTween();

        if (existingTween)
        {
            *existingTween = Tween(this, TweenType.Rotation, anglesFrom, anglesTo, duration, easing);
            return existingTween;
        }
        else
        {
            Tween t = Tween(this, TweenType.Rotation, anglesFrom, anglesTo, duration, easing);
            tweens.append(t);
            return &tweens.data[$-1];
        }
    }

    Tween* scaleFromTo(Vector3f sFrom, Vector3f sTo, double duration, Easing easing = Easing.Linear)
    {
        Tween* existingTween = getInactiveTween();

        if (existingTween)
        {
            *existingTween = Tween(this, TweenType.Scaling, sFrom, sTo, duration, easing);
            return existingTween;
        }
        else
        {
            Tween t = Tween(this, TweenType.Scaling, sFrom, sTo, duration, easing);
            tweens.append(t);
            return &tweens.data[$-1];
        }
    }

    AABB boundingBox() @property
    {
        if (drawable)
        {
            Mesh mesh = cast(Mesh)drawable;
            Terrain terrain = cast(Terrain)drawable;

            if (terrain)
            {
                mesh = terrain.mesh;
            }

            if (mesh)
            {
                auto bb = mesh.boundingBox;
                // TODO: transform bb with absoluteTransformation
                return AABB(absoluteTransformation.translation + bb.center, bb.size * matrixScale(absoluteTransformation));
            }
            else
                return aabb;
        }
        else
            return aabb;
    }

    ~this()
    {
        release();
    }

    void processEvents()
    {
        foreach(c; components)
        {
            c.processEvents();
        }
    }
}

class EntityComponent: EventListener, Updateable, Drawable
{
    Entity entity;

    this(EventManager em, Entity e)
    {
        super(em, e);
        entity = e;
        entity.addComponent(this);
    }

    // Override me
    void update(Time t)
    {
    }

    // Override me
    void render(GraphicsState* state)
    {
    }
}

interface EntityGroup
{
    int opApply(scope int delegate(Entity) dg);
}

Vector3f matrixScale(Matrix4x4f m)
{
    float sx = Vector3f(m.a11, m.a12, m.a13).length;
    float sy = Vector3f(m.a21, m.a22, m.a23).length;
    float sz = Vector3f(m.a31, m.a32, m.a33).length;
    return Vector3f(sx, sy, sz);
}
