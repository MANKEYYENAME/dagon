/*
Copyright (c) 2013-2019 Timur Gafarov 

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

module dagon.ext.physics.solver;

import std.math;
import std.algorithm;

import dlib.math.vector;
import dlib.math.utils;

import dagon.ext.physics.rigidbody;
import dagon.ext.physics.contact;

void prepareContact(Contact* c)
{
    if (!c.shape1.active || !c.shape2.active ||
        !c.shape1.solve || !c.shape2.solve)
        return;

    RigidBody body1 = c.body1;
    RigidBody body2 = c.body2;
    
    Vector3f r1 = c.body1RelPoint;
    Vector3f r2 = c.body2RelPoint;
    
    Vector3f relativeVelocity = Vector3f(0.0f, 0.0f, 0.0f);
    relativeVelocity += body1.linearVelocity + cross(body1.angularVelocity, r1);
    relativeVelocity -= body2.linearVelocity + cross(body2.angularVelocity, r2);
    c.initialVelocityProjection = dot(relativeVelocity, c.normal);

    c.n1 = c.normal;
    c.w1 = c.normal.cross(r1);
    c.n2 = -c.normal;
    c.w2 = -c.normal.cross(r2);

    c.effectiveMass = 
        body1.invMass + 
        body2.invMass +
        dot(c.w1 * body1.invInertiaTensor, c.w1) +
        dot(c.w2 * body2.invInertiaTensor, c.w2);
}

void solveContact(Contact* c, double dt)
{
    if (!c.shape1.active || !c.shape2.active ||
        !c.shape1.solve || !c.shape2.solve)
        return;

    RigidBody body1 = c.body1;
    RigidBody body2 = c.body2;
    
    Vector3f r1 = c.body1RelPoint;
    Vector3f r2 = c.body2RelPoint;

    Vector3f relativeVelocity = Vector3f(0.0f, 0.0f, 0.0f);
    relativeVelocity += body1.linearVelocity + cross(body1.angularVelocity, r1);
    relativeVelocity -= body2.linearVelocity + cross(body2.angularVelocity, r2);
    float velocityProjection = dot(relativeVelocity, c.normal);

    // Check if the bodies are already moving apart
    if (velocityProjection > 0.0f)
        return;

    float bounce = (body1.bounce + body2.bounce) * 0.5f;
    float damping = 0.9f;
    float C = max(0, -bounce * c.initialVelocityProjection - damping);

    float bias = 0.01f;

    // Velocity-based position correction
  /*
    float allowedPenetration = 0.01f;
    float biasFactor = 0.3f; // 0.1 to 0.3
    bias = biasFactor * (1.0f / dt) * max(0.0f, c.penetration - allowedPenetration);
  */
    float a = velocityProjection;
    float b = c.effectiveMass;

    float normalImpulse = (C - a + bias) / b;

    //if (normalImpulse < 0.0f)
    //    normalImpulse = 0.0f;

    // Friction
    float mu = (body1.friction + body2.friction) * 0.5f;
    Vector3f fVec = Vector3f(0.0f, 0.0f, 0.0f);

    Vector3f tn1 = c.fdir1;
    Vector3f tw1 = c.fdir1.cross(r1);
    Vector3f tn2 = -c.fdir1;
    Vector3f tw2 = -c.fdir1.cross(r2);
    float ta = dot(relativeVelocity, c.fdir1);
    float tb = dot(tn1, tn1 * body1.invMass)
             + dot(tw1, tw1 * body1.invInertiaTensor)
             + dot(tn2, tn2 * body2.invMass)
             + dot(tw2, tw2 * body2.invInertiaTensor);
    float fImpulse1 = -ta / tb;
    fImpulse1 = clamp(fImpulse1, -normalImpulse * mu, normalImpulse * mu);

    tn1 = c.fdir2;
    tw1 = c.fdir2.cross(r1);
    tn2 = -c.fdir2;
    tw2 = -c.fdir2.cross(r2);
    ta = dot(relativeVelocity, c.fdir2);
    tb = dot(tn1, tn1 * body1.invMass)
       + dot(tw1, tw1 * body1.invInertiaTensor)
       + dot(tn2, tn2 * body2.invMass)
       + dot(tw2, tw2 * body2.invInertiaTensor);
    float fImpulse2 = -ta / tb;
    fImpulse2 = clamp(fImpulse2, -normalImpulse * mu, normalImpulse * mu);

    c.accumulatedfImpulse1 += fImpulse1;
    c.accumulatedfImpulse2 += fImpulse2;

    fVec = c.fdir1 * fImpulse1 + c.fdir2 * fImpulse2;

    Vector3f impulseVec = c.normal * normalImpulse;

    body1.applyImpulse(+impulseVec, c.point);
    body2.applyImpulse(-impulseVec, c.point);
    
    if (body1.useFriction) body1.applyImpulse(+fVec, c.point);
    if (body2.useFriction) body2.applyImpulse(-fVec, c.point);
}

void solvePositionError(Contact* c, uint numContacts)
{
    RigidBody body1 = c.body1;
    RigidBody body2 = c.body2;
    
    Vector3f r1 = c.body1RelPoint;
    Vector3f r2 = c.body2RelPoint;
       
    Vector3f prv = Vector3f(0.0f, 0.0f, 0.0f);
    prv += body1.pseudoLinearVelocity + cross(body1.pseudoAngularVelocity, r1);
    prv -= body2.pseudoLinearVelocity + cross(body2.pseudoAngularVelocity, r2);
    float pvp = dot(prv, c.normal);

    if (c.penetration <= 0.0f)
        return;
    
    float ERP = (1.0f / numContacts) * 0.94f;
    float pc = c.penetration * ERP;
    //c.penetration -= pc;
    c.penetration = 0.0f;
    
    if (pvp >= pc)
        return;

    float a = pvp;
    float impulse = (pc - a) / c.effectiveMass;

    Vector3f impulseVec = c.normal * impulse;
   
    body1.applyPseudoImpulse(+impulseVec, c.point);
    body2.applyPseudoImpulse(-impulseVec, c.point);
}

