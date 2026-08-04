// File: Sources/NotchIsland/Island/Components/NotchShape.swift
import SwiftUI

/// A shape that reads as an extension of the physical notch: flat top edge,
/// concave (inverse) top corners that melt into the bezel, and large rounded
/// bottom corners. `topRadius` defaults to 0 for backward-compatible call sites.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let ir = max(0, min(topRadius, rect.width / 2 - 1))
        let br = max(0, min(bottomRadius, rect.height - ir - 1, rect.width / 2 - ir - 1))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))                          // flush top edge
        if ir > 0 {                                                                 // concave top-right
            p.addQuadCurve(to: CGPoint(x: rect.maxX - ir, y: rect.minY + ir),
                           control: CGPoint(x: rect.maxX - ir, y: rect.minY))
        }
        p.addLine(to: CGPoint(x: rect.maxX - ir, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - ir - br, y: rect.maxY),           // convex bottom-right
                       control: CGPoint(x: rect.maxX - ir, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + ir + br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + ir, y: rect.maxY - br),           // convex bottom-left
                       control: CGPoint(x: rect.minX + ir, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + ir, y: rect.minY + ir))
        if ir > 0 {                                                                 // concave top-left
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                           control: CGPoint(x: rect.minX + ir, y: rect.minY))
        }
        p.closeSubpath()
        return p
    }
}
